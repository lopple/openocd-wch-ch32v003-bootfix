/***************************************************************************
 *   WCH RISC-V mcu :CH32V103X CH32V20X CH32V30X CH56X CH57X CH58X         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program.  If not, see <http://www.gnu.org/licenses/>. *
 ***************************************************************************/

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "imp.h"
#include <helper/binarybuffer.h>
#include <target/algorithm.h>
#include <string.h>
extern int wlink_erase(void);
extern unsigned char riscvchip;
extern void wlink_reset();
extern void wlink_chip_reset(void);
extern void wlink_getromram(uint32_t *rom, uint32_t *ram);
extern int wlink_write(const uint8_t *buffer, uint32_t offset, uint32_t count);
extern bool noloadflag;
extern int wlink_flash_protect(bool stat);
extern int wlink_flash_protect_request(bool stat);
extern int wlnik_protect_check(void);
extern int wlink_is_open(void);
extern void wlink_clean(void);
extern int wlink_quitreset(void);
extern void wlink_chip(void);
extern unsigned long wlink_address;
extern unsigned long chipiaddr;
extern bool pageerase;
int writeloop =0 ;
extern unsigned int chip_type;
extern unsigned char wlink_detected_chip;
bool flash_unfreeze=false;

#define CH32V003_USER_FLASH_BASE 0x08000000U
#define CH32V003_USER_FLASH_SIZE 0x00004000U
#define CH32V003_BOOT_FLASH_BASE 0x1ffff000U
#define CH32V003_BOOT_FLASH_SIZE 0x00001000U
/* Avoid padded writes into the system identity area around 0x1ffff7e8. */
#define CH32V003_BOOT_WRITABLE_SIZE 0x00000780U
#define CH32V003_FLASH_STATR 0x4002200cU
#define CH32V003_FLASH_CTLR 0x40022010U
#define CH32V003_FLASH_OBR 0x4002201cU
#define CH32V003_FLASH_WPR 0x40022020U
#define CH32V003_OPTION_BYTES_BASE 0x1ffff800U
#define CH32V003_OPTION_BYTES_STATUS_SIZE 16U
#define CH32V003_OPTION_WRP_OFFSET 8U
#define CH32V003_OPTION_WRP_COUNT 4U

enum ch32vx_read_protect_status {
	CH32VX_READ_PROTECT_ENABLED = 4,
	CH32VX_READ_PROTECT_DISABLED = 5,
};

struct ch32vx_options
{
	uint8_t rdp;
	uint8_t user;
	uint16_t data;
	uint32_t protection;
};

struct ch32vx_flash_bank
{
	struct ch32vx_options option_bytes;
	int ppage_size;
	int probed;

	bool has_dual_banks;
	bool can_load_options;
	uint32_t register_base;
	uint8_t default_rdp;
	int user_data_offset;
	int option_offset;
	uint32_t user_bank_size;
};

FLASH_BANK_COMMAND_HANDLER(ch32vx_flash_bank_command)
{
	struct ch32vx_flash_bank *ch32vx_info;

	if (CMD_ARGC < 6)
		return ERROR_COMMAND_SYNTAX_ERROR;

	ch32vx_info = malloc(sizeof(struct ch32vx_flash_bank));

	bank->driver_priv = ch32vx_info;
	ch32vx_info->probed = 0;
	ch32vx_info->has_dual_banks = false;
	ch32vx_info->can_load_options = false;
	ch32vx_info->user_bank_size = bank->size;

	return ERROR_OK;
}

static target_addr_t ch32vx_target_address(struct flash_bank *bank, uint32_t offset)
{
	return bank->base + offset;
}

static uint32_t ch32vx_current_wlink_address(struct flash_bank *bank, uint32_t offset)
{
	uint32_t resolved = (uint32_t)(chipiaddr + ch32vx_target_address(bank, offset));

	if (resolved >= 0x10000000)
		resolved -= 0x08000000;

	return resolved;
}

static bool ch32vx_valid_erase_range(struct flash_bank *bank, int first, int last)
{
	return bank->sectors && first >= 0 && last >= first && last < (int)bank->num_sectors;
}

static bool ch32vx_full_bank_erase(struct flash_bank *bank, int first, int last)
{
	return ch32vx_valid_erase_range(bank, first, last)
		&& first == 0 && last == (int)bank->num_sectors - 1;
}

static bool ch32vx_is_ch32v003(void)
{
	return riscvchip == 0x09 && wlink_detected_chip != 0x49;
}

static bool ch32vx_read_protect_supported(void)
{
	return (riscvchip == 1) || (riscvchip == 5) || (riscvchip == 6)
		|| (riscvchip == 9) || (riscvchip == 0x4e) || (riscvchip == 0x0c)
		|| (riscvchip == 0x0e) || (riscvchip == 0x46)
		|| (riscvchip == 0x86) || (riscvchip == 0x8e);
}

static const char *ch32vx_read_protect_status_name(int status)
{
	switch (status) {
	case CH32VX_READ_PROTECT_ENABLED:
		return "enabled";
	case CH32VX_READ_PROTECT_DISABLED:
		return "disabled";
	default:
		return "unknown";
	}
}

static int ch32vx_read_protect_status(void)
{
	if (!wlink_is_open()) {
		LOG_ERROR("WCH read-protect/code-protect status requires initialized WCH-Link; run init first");
		return ERROR_FAIL;
	}

	if (riscvchip == 0 || wlink_detected_chip == 0) {
		LOG_ERROR("WCH read-protect/code-protect status requires a detected chip; run init first");
		return ERROR_FAIL;
	}

	if (!ch32vx_read_protect_supported()) {
		LOG_ERROR("Read-protect status command is not supported for chip=0x%02x detected=0x%02x",
			riscvchip, wlink_detected_chip);
		return ERROR_FAIL;
	}

	int status = wlnik_protect_check();
	if (status != CH32VX_READ_PROTECT_ENABLED
			&& status != CH32VX_READ_PROTECT_DISABLED) {
		LOG_ERROR("Failed to read WCH read-protect status for chip=0x%02x detected=0x%02x",
			riscvchip, wlink_detected_chip);
		return ERROR_FAIL;
	}

	if (!ch32vx_is_ch32v003()) {
		LOG_WARNING("Read-protect commands are release-gated for CH32V003; current chip=0x%02x detected=0x%02x",
			riscvchip, wlink_detected_chip);
	}

	return status;
}

static int ch32v003_print_raw_protection_status(struct command_invocation *cmd,
		struct target *target)
{
	uint32_t statr = 0;
	uint32_t ctlr = 0;
	uint32_t obr = 0;
	uint32_t wpr = 0;
	int retval;

	retval = target_read_u32(target, CH32V003_FLASH_STATR, &statr);
	if (retval != ERROR_OK)
		return retval;
	retval = target_read_u32(target, CH32V003_FLASH_CTLR, &ctlr);
	if (retval != ERROR_OK)
		return retval;
	retval = target_read_u32(target, CH32V003_FLASH_OBR, &obr);
	if (retval != ERROR_OK)
		return retval;
	retval = target_read_u32(target, CH32V003_FLASH_WPR, &wpr);
	if (retval != ERROR_OK)
		return retval;

	command_print(cmd, "CH32V003 FLASH raw registers: STATR=0x%08" PRIx32
		" CTLR=0x%08" PRIx32 " OBR=0x%08" PRIx32 " WPR=0x%08" PRIx32,
		statr, ctlr, obr, wpr);
	LOG_INFO("CH32V003 FLASH raw registers: STATR=0x%08" PRIx32
		" CTLR=0x%08" PRIx32 " OBR=0x%08" PRIx32 " WPR=0x%08" PRIx32,
		statr, ctlr, obr, wpr);

	uint8_t option_bytes[CH32V003_OPTION_BYTES_STATUS_SIZE];
	retval = target_read_buffer(target, CH32V003_OPTION_BYTES_BASE,
		sizeof(option_bytes), option_bytes);
	if (retval != ERROR_OK)
		return retval;

	command_print(cmd, "CH32V003 option bytes 0x%08x..0x%08x:"
		" %02x %02x %02x %02x %02x %02x %02x %02x"
		" %02x %02x %02x %02x %02x %02x %02x %02x",
		CH32V003_OPTION_BYTES_BASE,
		CH32V003_OPTION_BYTES_BASE + CH32V003_OPTION_BYTES_STATUS_SIZE - 1,
		option_bytes[0], option_bytes[1], option_bytes[2], option_bytes[3],
		option_bytes[4], option_bytes[5], option_bytes[6], option_bytes[7],
		option_bytes[8], option_bytes[9], option_bytes[10], option_bytes[11],
		option_bytes[12], option_bytes[13], option_bytes[14], option_bytes[15]);

	uint8_t wrp[CH32V003_OPTION_WRP_COUNT];
	bool all_wrp_ff = true;
	bool complement_ok = true;
	for (unsigned int i = 0; i < CH32V003_OPTION_WRP_COUNT; i++) {
		unsigned int offset = CH32V003_OPTION_WRP_OFFSET + i * 2;
		wrp[i] = option_bytes[offset];
		uint8_t nwrp = option_bytes[offset + 1];
		if (wrp[i] != 0xff)
			all_wrp_ff = false;
		if ((uint8_t)(wrp[i] ^ nwrp) != 0xff)
			complement_ok = false;
	}

	command_print(cmd, "CH32V003 WRP raw bytes: WRP0=0x%02x WRP1=0x%02x"
		" WRP2=0x%02x WRP3=0x%02x complement=%s",
		wrp[0], wrp[1], wrp[2], wrp[3],
		complement_ok ? "ok" : "mismatch");

	if (all_wrp_ff) {
		command_print(cmd, "CH32V003 write-protect summary: WRP bytes are all 0xff; no WRP-protected region is indicated.");
		LOG_INFO("CH32V003 write-protect summary: WRP bytes are all 0xff");
	} else {
		command_print(cmd, "CH32V003 write-protect summary: one or more WRP bytes are not 0xff; treat write-protect as active or unknown.");
		LOG_WARNING("CH32V003 write-protect summary: non-0xff WRP bytes detected");
	}

	if (!complement_ok) {
		command_print(cmd, "WARNING: WRP complement bytes do not match; use WCH-LinkUtility or datasheet-level inspection before changing protection.");
		LOG_WARNING("CH32V003 WRP complement bytes do not match");
	}

	return ERROR_OK;
}

static bool ch32vx_use_configured_bank_geometry(struct flash_bank *bank)
{
	return ch32vx_is_ch32v003() && bank->base != 0 && bank->size != 0;
}

static bool ch32v003_known_flash_bank(struct flash_bank *bank)
{
	return (bank->base == CH32V003_USER_FLASH_BASE
			&& bank->size > 0
			&& bank->size <= CH32V003_USER_FLASH_SIZE)
		|| (bank->base == CH32V003_BOOT_FLASH_BASE
			&& bank->size > 0
			&& bank->size <= CH32V003_BOOT_FLASH_SIZE);
}

static bool ch32vx_range_within(target_addr_t address, uint32_t count,
		target_addr_t base, uint32_t size)
{
	if (count == 0)
		return true;

	uint64_t start = (uint64_t)address;
	uint64_t end = start + (uint64_t)count - 1;
	uint64_t range_start = (uint64_t)base;
	uint64_t range_end = range_start + (uint64_t)size - 1;

	return end >= start && start >= range_start && end <= range_end;
}

static int ch32vx_validate_write_range(struct flash_bank *bank, uint32_t offset, uint32_t count)
{
	if (!ch32vx_is_ch32v003())
		return ERROR_OK;

	if (!ch32v003_known_flash_bank(bank)) {
		LOG_ERROR("Refusing CH32V003 write without explicit USER/BOOT flash bank:"
			" bank=%s base=" TARGET_ADDR_FMT " size=0x%08" PRIx32,
			bank->name, bank->base, bank->size);
		LOG_ERROR("Use tcl/target/wch-riscv-ch32v003.cfg or define USER 0x%08x/BOOT 0x%08x banks",
			CH32V003_USER_FLASH_BASE, CH32V003_BOOT_FLASH_BASE);
		return ERROR_FAIL;
	}

	target_addr_t address = ch32vx_target_address(bank, offset);

	if (ch32vx_range_within(address, count, CH32V003_USER_FLASH_BASE, CH32V003_USER_FLASH_SIZE)
			|| ch32vx_range_within(address, count, CH32V003_BOOT_FLASH_BASE, CH32V003_BOOT_WRITABLE_SIZE))
		return ERROR_OK;

	LOG_ERROR("Refusing CH32V003 write outside explicit USER/BOOT writable ranges:"
		" bank=%s base=" TARGET_ADDR_FMT " offset=0x%08" PRIx32
		" target_addr=" TARGET_ADDR_FMT " count=0x%08" PRIx32,
		bank->name, bank->base, offset, address, count);
	LOG_ERROR("Allowed CH32V003 write ranges: USER 0x%08x..0x%08x, BOOT writable 0x%08x..0x%08x",
		CH32V003_USER_FLASH_BASE,
		CH32V003_USER_FLASH_BASE + CH32V003_USER_FLASH_SIZE - 1,
		CH32V003_BOOT_FLASH_BASE,
		CH32V003_BOOT_FLASH_BASE + CH32V003_BOOT_WRITABLE_SIZE - 1);

	return ERROR_FAIL;
}

static void ch32vx_log_erase_request(struct flash_bank *bank, int first, int last)
{
	target_addr_t start = bank->base;
	target_addr_t end = bank->base;

	if (ch32vx_valid_erase_range(bank, first, last)) {
		start = bank->base + bank->sectors[first].offset;
		end = bank->base + bank->sectors[last].offset + bank->sectors[last].size - 1;
	}

	LOG_INFO("wch_riscv erase request: bank=%s base=" TARGET_ADDR_FMT
		" first=%d last=%d range=" TARGET_ADDR_FMT ".." TARGET_ADDR_FMT,
		bank->name, bank->base, first, last, start, end);

	if (ch32vx_is_ch32v003())
		LOG_WARNING("wch_riscv CH32V003 addressless erase is disabled unless page_erase bypasses this callback");
}

static int ch32vx_validate_erase_request(struct flash_bank *bank, int first, int last)
{
	if (!ch32vx_valid_erase_range(bank, first, last)) {
		LOG_ERROR("Refusing invalid erase range: bank=%s first=%d last=%d num_sectors=%u",
			bank->name, first, last, bank->num_sectors);
		return ERROR_FAIL;
	}

	if (ch32vx_is_ch32v003()) {
		if (ch32vx_full_bank_erase(bank, first, last))
			LOG_ERROR("Refusing CH32V003 addressless full-bank erase: bank=%s base="
				TARGET_ADDR_FMT " sectors=%u", bank->name, bank->base, bank->num_sectors);
		else
			LOG_ERROR("Refusing CH32V003 range erase because wlink_erase() has no address/range:"
				" bank=%s first=%d last=%d", bank->name, first, last);

		LOG_ERROR("Use the WCH page_erase write path only after independent USER/BOOT readback safety checks");
		return ERROR_FAIL;
	}

	if (!ch32vx_full_bank_erase(bank, first, last))
		LOG_WARNING("WCH erase command has no address/range; legacy path will still call wlink_erase()");

	return ERROR_OK;
}

static void ch32vx_log_write_request(struct flash_bank *bank, uint32_t offset, uint32_t count)
{
	LOG_INFO("wch_riscv write request: bank=%s base=" TARGET_ADDR_FMT
		" offset=0x%08" PRIx32 " target_addr=" TARGET_ADDR_FMT
		" count=0x%08" PRIx32
		" wlink_addr=0x%08" PRIx32,
		bank->name, bank->base, offset, ch32vx_target_address(bank, offset),
		count, ch32vx_current_wlink_address(bank, offset));
}

static int ch32x_protect(struct flash_bank *bank, int set, int first, int last)
{

	if (ch32vx_read_protect_supported())
	{
		LOG_WARNING("WCH flash protect command toggles read-protect/code-protect, not per-sector write-protect");
		if (!set) {
			LOG_WARNING("Disabling read-protect may erase or disturb USER flash; verify/rewrite USER flash after this operation");
		}
		int retval = wlink_flash_protect(set);
		if (retval == ERROR_OK)
		{
			if (set)
				LOG_INFO("Success to Enable Read-Protect");
			else
				LOG_INFO("Success to Disable Read-Protect");
			return ERROR_OK;
		}
		else
		{
			LOG_ERROR("Operation Failed");
			return ERROR_FAIL;
		}
	}
	else
	{
		LOG_ERROR("This chip do not support function");
		return ERROR_FAIL;
	}
}

static int ch32vx_erase(struct flash_bank *bank, int first, int last)
{

	if( (pageerase)||(writeloop!=0))
		return ERROR_OK;
	if ((riscvchip == 5) || (riscvchip == 6) || (riscvchip == 9)||  (riscvchip == 0x4e)|| (riscvchip == 0x0c)||(riscvchip==0x0e)||(riscvchip==0x46)||(riscvchip==0x0f)||(riscvchip==0x86)||(riscvchip==0x8e))
	{
		int retval = wlnik_protect_check();
		if (retval == CH32VX_READ_PROTECT_ENABLED)
		{
			LOG_ERROR("Read-Protect Status Currently Enabled");
			return ERROR_FAIL;
		}
	}
	if (noloadflag)
		return ERROR_OK;

	ch32vx_log_erase_request(bank, first, last);

	int retval = ch32vx_validate_erase_request(bank, first, last);
	if (retval != ERROR_OK)
		return retval;

	int ret = wlink_erase();
	target_halt(bank->target);
	
	if (ret)
		return ERROR_OK;
	else
		return ERROR_FAIL;
	return ERROR_OK;
}


static int ch32vx_write(struct flash_bank *bank, const uint8_t *buffer,
						uint32_t offset, uint32_t count)
{
	 wlink_chip();
	struct target *target = bank->target;
	if (((riscvchip == 5) || (riscvchip == 6) || (riscvchip == 9)|| (riscvchip == 0x4e)|| (riscvchip == 0x0c)||(riscvchip==0x0e)||(riscvchip==0x46)||(riscvchip==0x0f)) && (writeloop==0)||(riscvchip==0x86)||(riscvchip==0x8e))
	{
		int retval = wlnik_protect_check();
		if (retval == CH32VX_READ_PROTECT_ENABLED)
		{
			LOG_ERROR("Read-Protect Status Currently Enabled");
			return ERROR_FAIL;
		}
	}
	if (noloadflag)
		return ERROR_OK;
	
	if(writeloop)
		wlink_clean();
	int ret = 0;
	int mod = offset % 256;
	if (mod)
	{
		if (offset < 256)
			offset = 0;
		else
			offset -= mod;
		if (count > UINT32_MAX - mod) {
			LOG_ERROR("Refusing write with wrapped padded count: count=0x%08" PRIx32
				" mod=0x%08x", count, mod);
			return ERROR_FAIL;
		}
		uint32_t write_count = count + mod;
		int retval = ch32vx_validate_write_range(bank, offset, write_count);
		if (retval != ERROR_OK)
			return retval;
		uint32_t write_address = (uint32_t)ch32vx_target_address(bank, offset);
		uint8_t *buffer1;
		uint8_t *buffer2;
		buffer1 = malloc(write_count);
		buffer2 = malloc(mod);
		target_read_memory(bank->target, write_address, 1, mod, buffer2);
		memcpy(buffer1, buffer2, mod);
		memcpy(&buffer1[mod], buffer, count);
		ch32vx_log_write_request(bank, offset, write_count);
		ret = wlink_write(buffer1, write_address, write_count);
	}
	else
	{
		target_halt(target);
		int retval = ch32vx_validate_write_range(bank, offset, count);
		if (retval != ERROR_OK)
			return retval;
		uint32_t write_address = (uint32_t)ch32vx_target_address(bank, offset);
		ch32vx_log_write_request(bank, offset, count);
		ret = wlink_write(buffer, write_address, count);
	}

	// wlink_quitreset();
	//  target_halt(target);
	wlink_chip_reset();
		
	writeloop++;
	return ret;
}

static int ch32vx_get_device_id(struct flash_bank *bank, uint32_t *device_id)
{
	if ((riscvchip != 0x02) && (riscvchip != 0x03)&& (riscvchip != 0x07)&& (riscvchip != 0x0b)&&(riscvchip != 0x0f)&&(riscvchip != 0x4b)&&(riscvchip != 0x8e))
	{	
		struct target *target = bank->target;
		int retval = target_read_u32(target, 0x1ffff7e8, device_id);
		if (retval != ERROR_OK)
			return retval;
	}
	return ERROR_OK;
}

static int ch32vx_get_flash_size(struct flash_bank *bank, uint32_t *flash_size_in_kb)
{

	uint16_t flashsize;
	struct target *target = bank->target;
	if(riscvchip == 0x09)
	{
			*flash_size_in_kb = 0x7fffe;
		return ERROR_OK;


	}
	if ((riscvchip == 0x02) || (riscvchip == 0x03) || (riscvchip == 0x07)|| (riscvchip == 0x0b))
	{
		if((chip_type ==0x71000000) || (chip_type ==0x81000000) || (chip_type ==0x91000000)||(chip_type ==0x73550000))
				*flash_size_in_kb = 192;
		else
			*flash_size_in_kb = 448;
		return ERROR_OK;
	}
	if (riscvchip == 0x0c)
	{
		if(chip_type==0x03570601)
			*flash_size_in_kb = 48;
		*flash_size_in_kb = 62;
		return ERROR_OK;
	}
	if (riscvchip == 0x0e)
	{
		*flash_size_in_kb = 64;
		return ERROR_OK;
	}
	if(riscvchip == 0x46)
	{
			*flash_size_in_kb = 512;
		return ERROR_OK;

	}
		if(riscvchip == 0x0f)
	{
			*flash_size_in_kb = 448;
		return ERROR_OK;

	}
	if(riscvchip == 0x86)
	{
			*flash_size_in_kb = 480;
		return ERROR_OK;

	}
	if(riscvchip == 0x4b)
	{
			*flash_size_in_kb = 448;
		return ERROR_OK;

	}
	if(riscvchip == 0x8e)
	{
			*flash_size_in_kb = 64;
		return ERROR_OK;

	}
	if(riscvchip == 0x4e)
	{
		
		
		switch (chip_type>>20)
		{
			case 0x02:
			  *flash_size_in_kb = 16;
			  break;
			case 0x04:
            case 0x05:
			  *flash_size_in_kb = 32;
			  break;
			case 0x06:
			case 0x07:
			  *flash_size_in_kb = 62;
			  break;
           default:
		   LOG_ERROR("UNKNOW CHIP TYPE!");
		   return ERROR_FAIL;
		}
		return ERROR_OK;

	}
	int retval = target_read_u16(target, 0x1ffff7e0, &flashsize);
	*flash_size_in_kb=flashsize;
	if (retval != ERROR_OK)
		return retval;
	return ERROR_OK;
}

static int ch32vx_probe(struct flash_bank *bank)
{
	struct ch32vx_flash_bank *ch32vx_info = bank->driver_priv;
	uint16_t delfault_max_flash_size = 512;
	uint32_t flash_size_in_kb = 0;
	uint32_t device_id = 0;
	uint32_t rom = 0;
	uint32_t ram = 0;
	int page_size;
	uint32_t configured_size = (uint32_t)bank->size;
	bool use_configured_geometry = ch32vx_use_configured_bank_geometry(bank);
	uint32_t base_address = use_configured_geometry ? (uint32_t)bank->base : (uint32_t)wlink_address;
	uint32_t rid = 0;
	int num_pages;
	ch32vx_info->probed = 0;

	/* read ch32 device id register */
	int retval = ch32vx_get_device_id(bank, &device_id);
	if (retval != ERROR_OK)
		return retval;
	if (device_id)
		LOG_INFO("device id = 0x%08" PRIx32 "", device_id);
	page_size = 1024;
	ch32vx_info->ppage_size = 4;

	if (use_configured_geometry) {
		num_pages = (configured_size + page_size - 1) / page_size;
		LOG_INFO("CH32V003 configured flash bank: base=" TARGET_ADDR_FMT
			" size=0x%08" PRIx32 " pages=%d",
			bank->base, configured_size, num_pages);
	} else {
		/* get flash size from target. */
		retval = ch32vx_get_flash_size(bank, &flash_size_in_kb);
		if (retval != ERROR_OK)
			return retval;

		if ((flash_size_in_kb)&&(!flash_unfreeze)&&(riscvchip !=0x09))
			LOG_INFO("flash size = %dkbytes", flash_size_in_kb);
		else
			flash_size_in_kb = delfault_max_flash_size;
		num_pages = flash_size_in_kb * 1024 / page_size;
	}
	if ((riscvchip == 0x05) || (riscvchip == 0x06)|| (riscvchip == 0x86))
	{
		wlink_getromram(&rom, &ram);
		if ((rom != 0) && (ram != 0))
			LOG_INFO("ROM %d kbytes RAM %d kbytes", rom, ram);
	}
	// /* calculate numbers of pages */
	bank->base = base_address;
	bank->size = (num_pages * page_size);
	bank->num_sectors = num_pages;
	bank->sectors = alloc_block_array(0, page_size, num_pages);
	ch32vx_info->probed = 1;

	return ERROR_OK;
}

static int ch32vx_auto_probe(struct flash_bank *bank)
{

	struct ch32vx_flash_bank *ch32vx_info = bank->driver_priv;
	if (ch32vx_info->probed)
		return ERROR_OK;
	return ch32vx_probe(bank);
}

COMMAND_HANDLER(ch32vx_handle_unfreeze_command)
{

	flash_unfreeze=true;
	return ERROR_OK;
}

COMMAND_HANDLER(ch32vx_handle_read_protect_status_command)
{
	if (CMD_ARGC != 0)
		return ERROR_COMMAND_SYNTAX_ERROR;

	int status = ch32vx_read_protect_status();
	if (status < 0)
		return status;

	command_print(CMD, "WCH read-protect/code-protect status: %s",
		ch32vx_read_protect_status_name(status));
	LOG_INFO("WCH read-protect/code-protect status: %s",
		ch32vx_read_protect_status_name(status));

	return ERROR_OK;
}

COMMAND_HANDLER(ch32vx_handle_protection_status_command)
{
	if (CMD_ARGC != 0)
		return ERROR_COMMAND_SYNTAX_ERROR;

	int status = ch32vx_read_protect_status();
	if (status < 0)
		return status;

	command_print(CMD, "WCH read-protect/code-protect status: %s",
		ch32vx_read_protect_status_name(status));
	LOG_INFO("WCH read-protect/code-protect status: %s",
		ch32vx_read_protect_status_name(status));

	if (!ch32vx_is_ch32v003()) {
		command_print(CMD, "CH32V003 option/WRP raw status is not available for chip=0x%02x detected=0x%02x.",
			riscvchip, wlink_detected_chip);
		return ERROR_OK;
	}

	if (status == CH32VX_READ_PROTECT_ENABLED) {
		command_print(CMD, "CH32V003 option/WRP target-memory read skipped because read-protect is enabled.");
		command_print(CMD, "Do not infer WRP from target memory while read-protect is enabled; query WCH-LinkUtility or disable read-protect only with USER erase approval.");
		LOG_WARNING("CH32V003 option/WRP raw read skipped because read-protect is enabled");
		return ERROR_OK;
	}

	struct target *target = get_current_target(CMD_CTX);
	if (!target) {
		LOG_ERROR("No current target; cannot read CH32V003 option/WRP status");
		return ERROR_FAIL;
	}

	int retval = ch32v003_print_raw_protection_status(CMD, target);
	if (retval != ERROR_OK) {
		LOG_ERROR("Failed to read CH32V003 option/WRP raw status");
		command_print(CMD, "Failed to read CH32V003 option/WRP raw status.");
		return retval;
	}

	return ERROR_OK;
}

COMMAND_HANDLER(ch32vx_handle_disable_read_protect_command)
{
	const char *confirmation = "confirm-user-flash-erase";

	if (CMD_ARGC != 1 || strcmp(CMD_ARGV[0], confirmation) != 0) {
		LOG_ERROR("Refusing to disable read-protect without explicit confirmation");
		LOG_ERROR("Disabling CH32 read-protect may erase or disturb USER flash");
		LOG_ERROR("Usage: wch_riscv disable_read_protect %s", confirmation);
		command_print(CMD, "Refusing to disable read-protect without explicit confirmation.");
		command_print(CMD, "This operation may erase or disturb USER flash.");
		command_print(CMD, "Usage: wch_riscv disable_read_protect %s", confirmation);
		return ERROR_COMMAND_SYNTAX_ERROR;
	}

	int status = ch32vx_read_protect_status();
	if (status < 0) {
		command_print(CMD, "Failed to read current read-protect/code-protect status.");
		command_print(CMD, "Run init first and retry before changing protection.");
		return status;
	}

	if (status == CH32VX_READ_PROTECT_DISABLED) {
		command_print(CMD, "WCH read-protect/code-protect is already disabled.");
		LOG_INFO("WCH read-protect/code-protect is already disabled");
		return ERROR_OK;
	}

	LOG_WARNING("Disabling CH32 read-protect/code-protect now");
	LOG_WARNING("USER flash may be erased or disturbed by this operation");
	LOG_WARNING("After disable, verify BOOT readback and rewrite/verify USER flash from a known image");
	command_print(CMD, "WARNING: disabling CH32 read-protect/code-protect now.");
	command_print(CMD, "WARNING: USER flash may be erased or disturbed.");

	int retval = wlink_flash_protect_request(false);
	if (retval != ERROR_OK) {
		LOG_ERROR("Failed to disable WCH read-protect/code-protect");
		return retval;
	}

	status = ch32vx_read_protect_status();
	if (status < 0) {
		command_print(CMD, "WCH read-protect/code-protect disable request was accepted.");
		command_print(CMD, "WARNING: final status read failed; reconnect and verify USER/BOOT flash.");
		LOG_WARNING("WCH read-protect/code-protect disable request was accepted, but final status read failed");
		return ERROR_OK;
	}
	if (status != CH32VX_READ_PROTECT_DISABLED) {
		LOG_ERROR("Read-protect disable command completed but final status is %s",
			ch32vx_read_protect_status_name(status));
		return ERROR_FAIL;
	}

	command_print(CMD, "WCH read-protect/code-protect disabled.");
	command_print(CMD, "USER flash may have been erased; rewrite/verify USER flash from a known image.");
	LOG_WARNING("WCH read-protect/code-protect disabled; USER flash may have been erased");

	return ERROR_OK;
}


static const struct command_registration ch32vx_exec_command_handlers[] = {
	{
		.name = "unfreeze",
		.handler = ch32vx_handle_unfreeze_command,
		.mode = COMMAND_EXEC,
		.usage = "",
		.help = "unfreeze entire flash device.",
	},
	{
		.name = "read_protect_status",
		.handler = ch32vx_handle_read_protect_status_command,
		.mode = COMMAND_ANY,
		.usage = "",
		.help = "read WCH read-protect/code-protect status.",
	},
	{
		.name = "protection_status",
		.handler = ch32vx_handle_protection_status_command,
		.mode = COMMAND_ANY,
		.usage = "",
		.help = "read WCH read-protect status and CH32V003 raw option/WRP status.",
	},
	{
		.name = "disable_read_protect",
		.handler = ch32vx_handle_disable_read_protect_command,
		.mode = COMMAND_ANY,
		.usage = "confirm-user-flash-erase",
		.help = "disable WCH read-protect/code-protect after explicit confirmation.",
	},
	COMMAND_REGISTRATION_DONE
};
static const struct command_registration ch32vx_command_handlers[] = {
	{
		.name = "wch_riscv",
		.mode = COMMAND_ANY,
		.help = "wch_riscv flash command group",
		.usage = "",
		.chain = ch32vx_exec_command_handlers,
	},
	COMMAND_REGISTRATION_DONE};

const struct flash_driver wch_riscv_flash = {
	.name = "wch_riscv",
	.commands = ch32vx_command_handlers,
	.flash_bank_command = ch32vx_flash_bank_command,
	.erase = ch32vx_erase,
	.protect = ch32x_protect,
	.write = ch32vx_write,
	.read = default_flash_read,
	.probe = ch32vx_probe,
	.auto_probe = ch32vx_auto_probe,
	.erase_check = default_flash_blank_check,
	.free_driver_priv = default_flash_free_driver_priv,
};
