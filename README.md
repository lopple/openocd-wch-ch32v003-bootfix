# OpenOCD WCH CH32V003 BOOT Write Fix

This is a hard fork of WCH OpenOCD focused on safe writes to the CH32V003 BOOT/system storage area at `0x1ffff000`.

Project policy:

- Use the WCH OpenOCD source mirror from `cjacker/wch-openocd` as the maintenance base for this hard fork.
- Treat `openwch/openocd_wch` as a binary distribution and Arduino package index compatibility reference, not as the source maintenance base.
- Use `Seneral/riscv-openocd-wch` as a comparison reference for WCH-LinkE/SDI behavior.
- Keep CH32V003 USER flash at `0x08000000` and BOOT/system storage at `0x1ffff000` as separate address ranges.
- Do not accept OpenOCD `verify OK` alone as proof of success. Always confirm with independent USER flash and BOOT flash readback/hash checks.

## Windows Release Scope

The current Windows release is intentionally limited to `windows-x86` / `i686-mingw32` / WCHLinkDLL backend.

- It assumes the WCH official driver stack installed by WCH-LinkUtility or the WCH official driver package.
- `WCHLinkDLL.dll` and `CH347DLL.dll` are not bundled in the release zip.
- Driver replacement with Zadig, WinUSB, or libusbK is outside this release scope.
- A successful BOOT write requires OpenOCD verify, matching BOOT readback, and unchanged USER flash hash.

## Windows User Notes

- Install WCH-LinkUtility or the WCH official driver before using this release on Windows.
- This release targets the WCH official driver stack. WinUSB/libusbK configurations are not supported.
- Replacing the WCH driver with Zadig is not recommended, because coexistence with WCH-LinkUtility is prioritized.
- `WCHLinkDLL.dll` is loaded dynamically from the OS or WCH official driver stack location. It is not included in the archive.

## Basic Use

Download the binary release asset from GitHub Releases. For Arduino Boards Manager or other tool archives, use the fixed release asset URL under `/releases/download/<tag>/...zip`, not GitHub's auto-generated source archives.

After extracting the zip, use `bin/openocd.exe` together with `share/openocd/scripts` from the archive.

```powershell
bin\openocd.exe -s share\openocd\scripts -f target\wch-riscv-ch32v003.cfg
```

For CH32V003 BOOT writes, read back USER flash and BOOT/system storage before and after the write. Confirm that BOOT readback matches the requested image and that the USER flash hash is unchanged.

## Packaging and Release Policy

- [docs/changes-from-upstream.md](docs/changes-from-upstream.md)
- [docs/license-and-release-policy.md](docs/license-and-release-policy.md)
- [docs/roadmap.md](docs/roadmap.md)
- [docs/manual-release-gate.md](docs/manual-release-gate.md)
- [docs/public-import.md](docs/public-import.md)
- [packaging/windows/README.md](packaging/windows/README.md)
- [packaging/arduino/README.md](packaging/arduino/README.md)

## Source Base

The OpenOCD code in this repository starts from the WCH OpenOCD source mirror in `cjacker/wch-openocd`.
This project does not claim that `cjacker/wch-openocd` is the exact corresponding source for the `openwch/openocd_wch` 1.0.0 binary distribution. It is treated as a maintainable hard-fork base derived from the 2024-11-26 WCH OpenOCD source mirror.

In the public history, the first commit is the imported upstream snapshot. Later commits contain the hard-fork changes. The comparison base is `upstream/cjacker-2024-11-26`:

```sh
git diff upstream/cjacker-2024-11-26..main
```

The `openwch/openocd_wch` 1.0.0 repository appears to use xPack OpenOCD as the default source in its build scripts, while the bundled `openocd.exe` still contains WCH/MounRiver patch traces such as `wlinke.c`, `wchriscv.c`, `wch_riscv`, and `wlink_set_address`. Therefore, this project treats that binary as likely produced from an xPack-style distribution framework plus WCH/MounRiver patches or a separate source tree that is not included there. It is not used as this hard fork's corresponding source or release binary.

The imported upstream README describes the source as follows:

This repo is the latest source of WCH OpenOCD **(2024-11-26 version)**.

- support WCH-Link / LinkE / LinkS / LinkW debuggers with latest firmware.
- support program / debug all WCH ch32v/x/l series MCUs and some MCU models in future.

Up to 2024-11-26, the laste firmware version:

- WCH-Link (CH549): v2.12
- WCH-LinkE (CH32V305FBP6): v2.15

**To update to latest firmware, read "[how to update firmware of WCH-Link/LinkE](https://github.com/cjacker/opensource-toolchain-ch32v#how-to-update-firmware-of-wch-linke)". If you didn't update firmware of WCH-Link/E, you may have to use [old version WCH OpenOCD](https://github.com/cjacker/wch-openocd-2022).**

## Installation

```
./bootstrap
./configure --prefix=/opt/wch-openocd --enable-wlinke --disable-ch347 --disable-linuxgpiod --disable-werror --program-prefix=wch-
make
sudo make install
```

After installation successfully, please add `/opt/wch-openocd/bin` to your PATH env.

## Usage

```
wch-openocd -f /opt/wch-openocd/share/openocd/scripts/target/wch-riscv.cfg

```

You may copy `wch-riscv.cfg` to your project dir to avoid such long file path.
