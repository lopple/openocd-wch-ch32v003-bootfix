# Changes from upstream

This repository keeps a public comparison point named
`upstream/cjacker-2024-11-26`.

The first commit is the imported `cjacker/wch-openocd` source snapshot:

- upstream repository: <https://github.com/cjacker/wch-openocd>
- upstream commit: `2b6802dde74a9560bdfb6eeecb6aff8a13cf8139`
- upstream note: WCH OpenOCD 2024-11-26 source mirror

To inspect the hard-fork changes:

```sh
git diff upstream/cjacker-2024-11-26..main
```

## Source changes

- `src/flash/nor/wchriscv.c`
  - separates CH32V003 USER flash `0x08000000` and BOOT/system storage
    `0x1ffff000`
  - validates CH32V003 write ranges before WCH-Link transfer
  - rejects addressless erase through the unsafe legacy erase path for CH32V003
  - logs bank, target address, and resolved WCH-Link address for writes
  - adds `read_protect_status`, `protection_status`, and
    `disable_read_protect confirm-user-flash-erase` commands
  - requires an initialized WCH-Link target session before reading or changing
    protection state
  - logs USER flash erase risk before disabling read-protect/code-protect
- `src/jtag/drivers/wlinke.c`
  - keeps BOOT writes at `0x1ffff000`
  - limits CH32V003 BOOT write padding to the writable `0x1ffff000..0x1ffff77f`
    range
  - adds final write-plan logging and a write-plan trap before flash transfer
  - keeps the Windows WCHLinkDLL backend behind `--enable-wlinke-ch375-dll`
  - preserves the legacy `code_erase CH32V003` command shape while adding
    risk logging and raw response diagnostics
- `tcl/target/wch-riscv-ch32v003.cfg`
  - defines explicit CH32V003 USER and BOOT flash banks
- `src/helper/startup.tcl`
  - sources scripts through an opened file so Windows paths from release staging
    work consistently

## Release and validation changes

- Adds Windows x86 / i686-mingw32 GitHub Actions workflows.
- Adds release staging, DLL/import audit, targetless smoke test, and zip/hash
  generation scripts.
- Adds CH32V003 BOOT write release-gate helper that records USER/BOOT readback
  hashes and supports write-plan trap validation.
- Documents that Windows release assets are for the WCH official driver stack
  and do not bundle `WCHLinkDLL.dll` or `CH347DLL.dll`.

## Not included

The public repository intentionally does not import private investigation
history, hardware readback dumps, bootloader test images, local build outputs,
or private release evidence.
