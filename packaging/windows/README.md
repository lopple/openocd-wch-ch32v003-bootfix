# Windows Release Zip Policy

## Goal

Produce a Windows OpenOCD zip with a fixed URL, checksum, and size so it can be consumed easily by Arduino Boards Manager and similar tooling.

## Principles

- Build from a tag in this hard-fork repository.
- Do not use the existing `openocd.exe` from `openwch/openocd_wch`.
- Do not bundle WCH proprietary DLLs.
- Before zipping, verify `bin/openocd.exe --version` and startup with `-f scripts/target/wch-riscv.cfg` from the staged layout.

## Current Release Scope

The current Windows release is intentionally limited to the WCH official driver stack.

- package label: `windows-x86`
- Arduino host: `i686-mingw32`
- backend: WCHLinkDLL backend
- driver requirement: WCH official driver stack installed by WCH-LinkUtility or the WCH official driver package
- `WCHLinkDLL.dll` / `CH347DLL.dll`: not bundled in the release zip
- WinUSB/libusbK: out of scope for this release

Configurations that replace the driver with Zadig, WinUSB, or libusbK are unsupported. This release does not recommend driver replacement because coexistence with WCH-LinkUtility is prioritized.

Successful BOOT writes require matching BOOT readback and unchanged USER flash hash, not OpenOCD verify alone.

## WCH Internal Protocol Boundary

WCH-LinkUtility, WCHLinkDLL, and WCH-Link firmware protocol details are not treated as a public, stable specification for this release. WCH-specific legacy adapter commands such as `code_erase CH32V003` may remain available for compatibility, but they are not release-validated recovery features unless a report explicitly records destructive hardware validation and WCH-LinkUtility comparison.

For this release, `code_erase` is documented as a preserved WCH legacy command with improved raw ACK/risk logging only. Do not present it as an OpenOCD replacement for WCH-LinkUtility `Clear All Code Flash-By Pin NRST`.

## Required Build Artifact Process

Only zips that satisfy every step below may be considered Windows release artifacts.

1. Build `openocd.exe` from the hard-fork source without reusing official distribution binaries.
2. Collect build output into a clean staging directory.
3. Audit the DLL/import table of `openocd.exe` and confirm that there are no missing DLLs, DLLs with unclear redistribution terms, or unexpected runtime dependencies.
4. Create or stage `COPYING`, `LICENSES/`, `NOTICE.txt`, `SOURCE.txt`, and `BUILDINFO.txt`.
5. Run targetless smoke tests using only the staging directory as input.
6. Create the zip and pin the archive filename, SHA256, and byte size.

Do not use a zip that fails this process as a release asset or Arduino Boards Manager tool archive.

## Zip Layout

```text
openocd-wch-ch32v003-bootfix-<version>-windows-<arch>/
  bin/
    openocd.exe
  scripts/
    target/wch-riscv.cfg
    ...
  share/openocd/scripts/
    target/wch-riscv.cfg
    ...
  COPYING
  LICENSES/
  NOTICE.txt
  README.md
  SOURCE.txt
  BUILDINFO.txt
  DLL-IMPORTS.txt
  LICENSE-AND-RELEASE-POLICY.md
  SHA256SUMS.txt
```

## Bundling Policy

Bundle:

- `openocd.exe` built from this fork
- MinGW/runtime DLLs required for execution
- `scripts/` or target/interface cfg files referenced by OpenOCD
- `COPYING`, `LICENSES/`, `NOTICE.txt`
- Source commit, build information, and DLL/import audit records

Generate `NOTICE.txt` from `packaging/windows/NOTICE.template.txt` by filling in the release version, source commit, tag, and bundled runtime DLL list.

Do not bundle:

- `WCHLinkDLL.dll`
- `CH347DLL.dll`
- `openwch/openocd_wch/bin/openocd.exe`
- Local experiment readbacks, bootloader images, or customer data

## Pre-release Checklist

1. Source tag and build commit are recorded.
2. `git status --short` shows the intended state.
3. The binary was built from this hard-fork source without reusing official distribution binaries.
4. Build output was collected into a clean staging directory.
5. The DLL/import table of `openocd.exe` was audited, and runtime dependencies plus bundle/do-not-bundle decisions were recorded.
6. `COPYING`, `LICENSES/`, `NOTICE.txt`, `SOURCE.txt`, `BUILDINFO.txt`, and `DLL-IMPORTS.txt` were placed in the staging directory.
7. `openocd.exe --version` works using only the staged relative layout.
8. WCH target configs resolve using only cfg files from the staging directory.
9. CH32V003 BOOT write validation shows matching USER flash pre/post hashes.
10. BOOT readback hash matches the expected image.
11. `SHA256SUMS.txt` and the zip byte size are recorded.
12. The release body includes the source URL, commit, zip SHA256, byte size, and known limitations.

## GitHub release asset

The release asset URL must be the fixed GitHub release asset URL.

```text
https://github.com/<owner>/<repo>/releases/download/<tag>/openocd-wch-ch32v003-bootfix-<version>-windows-<arch>.zip
```

Do not use GitHub codeload auto-generated source zips as Arduino package index tool archives.

## GitHub Actions Operation

CI is split into two stages.

- `Windows x86 artifact`: build an artifact zip from a candidate branch commit. This does not create a release.
- `Windows release draft`: when a `v*` tag is pushed, run the same build process and upload the asset to a GitHub draft prerelease.

Before publishing the draft release, pass the [manual release gate](../../docs/manual-release-gate.md). In particular, BOOT write success requires matching BOOT readback and unchanged USER flash hash, not OpenOCD verify alone.

For Arduino package index entries, use only the URL, SHA256, and byte size from the published release asset after downloading and rehashing it.

## Windows arch status

As of 2026-06-23, the release candidate is `windows-x86` / `i686-mingw32`.

- Use a 32-bit MinGW/WCHLinkDLL backend build with the driver stack installed by WCH-LinkUtility.
- The `openocd.exe` import table contains `KERNEL32.dll`, `msvcrt.dll`, `USER32.dll`, and `WS2_32.dll`.
- `WCHLinkDLL.dll` / `CH347DLL.dll` are not bundled in the release zip.
- The Windows environment is expected to have the WCH driver stack installed by WCH-LinkUtility or equivalent WCH official tooling.
- Driver replacement with Zadig, WinUSB, or libusbK is outside this release scope.
- USB enumeration depends on the USER firmware, so it is not used as a release criterion.
- Validation is based on OpenOCD readback/hash evidence, and USER flash hash must remain unchanged after BOOT write.

Release asset in the public repository:

```text
tag: v0.11.0-ch32v003bootfix.2
source commit: 846f2cf5d057bf257ed5cfe21417983630099dc9
workflow run: https://github.com/lopple/openocd-wch-ch32v003-bootfix/actions/runs/28009722292
archiveFileName: openocd-wch-ch32v003-bootfix-0.11.0-ch32v003bootfix.2-windows-x86-wchdriver.zip
url: https://github.com/lopple/openocd-wch-ch32v003-bootfix/releases/download/v0.11.0-ch32v003bootfix.2/openocd-wch-ch32v003-bootfix-0.11.0-ch32v003bootfix.2-windows-x86-wchdriver.zip
openocd.exe version: 0.11.0+dev (2026-06-23-07:30)
openocd.exe SHA256: 36A5926EFC44BC67AB41D46485A93BEA36E3920437715C4493BA424E492D5782
zip size: 8176825
zip SHA256: F4D10EE0D8629BA4EBAA2980BB31159825F7C2766D91CCD935CE85472CED835C
```

These values were fixed after building the release asset from the public repository tag with GitHub Actions, publishing it, downloading it again, and confirming that SHA256/size matched the sidecar and Gate C record. Only assets that pass targetless smoke testing, release text/import audit, write-plan trap, and hardware BOOT write/readback are distributable. USER flash full/head hashes must match pre/post write, and the BOOT readback prefix must match the input bootloader.

This release asset includes `NOTICE.txt` and DLL/import audit records. It does not bundle WCH proprietary DLLs.

## Future Release Roadmap

Future release candidates, WinUSB/libusbK backend work, asset separation, and dependency/license audit automation are tracked in [../../docs/roadmap.md](../../docs/roadmap.md).
