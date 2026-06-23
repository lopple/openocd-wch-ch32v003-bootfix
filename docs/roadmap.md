# Roadmap

Created: 2026-06-23 JST

## Current Release Boundary

The current Windows release is intentionally limited to the WCH official driver stack.

- `windows-x86` / `i686-mingw32`
- WCHLinkDLL backend
- WCH official driver stack installed by WCH-LinkUtility or the WCH official driver package
- `WCHLinkDLL.dll` and `CH347DLL.dll` are not bundled in the release zip
- WinUSB/libusbK configurations are not supported
- Driver replacement with Zadig is not recommended
- A successful BOOT write requires OpenOCD verify, matching BOOT readback, and unchanged USER flash hash

This release does not attempt to add WinUSB/libusbK support. It prioritizes coexistence with WCH-LinkUtility and treats the WCH official driver stack as the supported driver path.

## Future Release Roadmap

### 1. Re-check `windows-x64` Builds

- Identify a backend that can open WCH-Link reliably from a 64-bit build.
- Decide whether a 64-bit WCHLinkDLL is required or whether libusb/WinUSB should be used.
- Ship this as a separate asset from the 32-bit WCHLinkDLL backend release.

### 2. WinUSB/libusbK backend build

- Identify the exact interface that should be replaced with Zadig or an equivalent tool.
- Check whether it can coexist with WCH-LinkUtility.
- Document how to restore the WCH official driver stack.
- Use a separate zip and asset name from the WCH official driver release.

### 3. Release Asset Separation

Release asset names must include the backend and driver assumption.

Examples:

```text
openocd-wch-<version>-windows-x86-wchdriver.zip
openocd-wch-<version>-windows-x64-winusb.zip
```

Arduino package index entries must reference only hardware-verified assets. Do not publish unverified backend or architecture assets as Boards Manager tool archives.

### 4. Automated Dependency and License Audit

- Make the release check fail if the import table contains `WCHLinkDLL.dll`, `CH347DLL.dll`, `JLinkARM.dll`, or `FTD2XX.dll`.
- Make the release check fail if the release zip bundles `WCHLinkDLL.dll`, `CH347DLL.dll`, `JLinkARM.dll`, or `FTD2XX.dll`.
- If DLLs are bundled, they must be recorded in `LICENSES/` and `THIRD_PARTY_NOTICES.md`.
- Verify generation of `SOURCE.txt`, `BUILDINFO.txt`, `NOTICE.txt`, and `SHA256SUMS.txt` in CI.

## Release Rule

Every release asset must state its driver stack, backend, and architecture in the asset name and README.

Do not mix multiple backends in a single zip. WCH official driver stack releases and WinUSB/libusbK releases must be separate assets, with separate validation and separate known limitations.
