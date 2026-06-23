# License and Release Policy

Created: 2026-06-22 JST

## Conclusion

This hard fork modifies source derived from `cjacker/wch-openocd` and is distributed as a GPL-2.0-or-later OpenOCD fork. Windows release assets contain only `openocd.exe` built from this fork and the required runtime/config/license files.

This project does not claim that `cjacker/wch-openocd` is the exact corresponding source for the `openwch/openocd_wch` 1.0.0 binary distribution. It is treated as a maintainable hard-fork source base derived from the 2024-11-26 WCH OpenOCD source mirror.

The existing `bin/openocd.exe` from `openwch/openocd_wch` is used only as comparison evidence. It is not reused in this hard fork's release assets. WCH proprietary DLLs such as `WCHLinkDLL.dll` and `CH347DLL.dll` are not bundled unless their redistribution terms are clear.

## Basis

Confirmed source-side licensing:

- `COPYING`: OpenOCD as a whole is `GPL-2.0-or-later`.
- `src/flash/nor/wchriscv.c`: has a GPL v2 or later header.
- `src/jtag/drivers/wlinke.c`: has a GPL v2 or later header.
- `LICENSES/license-rules.txt`: explains the license rules for the OpenOCD source tree and individual files.

Confirmed distribution-side observations:

- `openwch/openocd_wch` mainly contains `bin/`, `scripts/`, `share/`, and `distro-info/`. It does not include the OpenOCD source tree with the WCH-specific driver code.
- `openwch/openocd_wch/README.md` directs users to contact MounRiver support for source and build procedure details.
- The default `OPENOCD_GIT_URL` in `openwch/openocd_wch/distro-info/scripts/build-native.sh` is `https://github.com/xpack-dev-tools/openocd.git`.
- At the same time, `openwch/openocd_wch/bin/openocd.exe` contains WCH-specific strings such as `src/jtag/drivers/wlinke.c`, `src/flash/nor/wchriscv.c`, `wch_riscv`, `wlink_set_address`, and `_wch_riscv_flash`.
- Arduino package index friendly assets should be fixed binary release assets from this hard fork, not source zip archives.

## Source Origin Inference

Looking only at the build scripts in the repository, `openwch/openocd_wch` 1.0.0 looks like an xPack OpenOCD-derived distribution. However, the bundled binary contains WCH-specific driver and flash driver strings, which cannot be explained as stock xPack OpenOCD.

Therefore, the `openwch/openocd_wch` 1.0.0 binary distribution is inferred to have been produced from an xPack-style distribution/build framework combined with WCH/MounRiver patches or a separate source tree that is not included there. That repository alone does not identify the corresponding C source for `wlinke.c` / `wchriscv.c`.

`cjacker/wch-openocd` describes itself in its README as the "Latest source of official WCH OpenOCD (2024-11-26 version)" and contains a normal OpenOCD source tree including WCH-specific `wlinke.c` / `wchriscv.c`. This project therefore uses `cjacker/wch-openocd` as the hard-fork source base. Release notes must still say that this fork is derived from the `cjacker/wch-openocd` mirror, not that it is the exact corresponding source for the `openwch/openocd_wch` 1.0.0 binary.

Upstream import record: `upstream-metadata/cjacker-wch-openocd-import.md`

## Release Requirements

Required:

- The corresponding source must be available from this hard-fork repository tag.
- Build `openocd.exe` from the hard-fork source. Do not reuse existing official binaries such as `openwch/openocd_wch`.
- Collect build output into a clean staging directory, and use only that staging directory as the release zip input.
- Audit the DLL/import table of `openocd.exe` and record missing DLLs, DLLs with unclear redistribution terms, and unexpected runtime dependencies.
- Include `COPYING`, `LICENSES/`, `NOTICE.txt`, `SOURCE.txt`, `BUILDINFO.txt`, `DLL-IMPORTS.txt`, and `SHA256SUMS.txt` in the Windows zip.
- Record in `NOTICE.txt` that this is an OpenOCD fork, the main source base, bundled runtimes, and WCH proprietary DLLs that are not redistributed.
- Record the source repository URL, commit hash, tag, and main patch summary in `SOURCE.txt`.
- Record build host, toolchain, configure options, and runtime DLL list in `BUILDINFO.txt`.
- Run targetless smoke tests using only the staging directory.
- After creating the zip, fix the archive filename, SHA256, and byte size.
- Record the source tag, Windows zip SHA256, and byte size in the GitHub release body.

Forbidden:

- Do not redistribute `openwch/openocd_wch/bin/openocd.exe` as a hard-fork release asset.
- Do not treat the `openwch/openocd_wch` 1.0.0 tag source zip as the corresponding source for the hard-fork binary.
- Do not bundle WCH proprietary DLLs with unclear redistribution terms, including `WCHLinkDLL.dll` and `CH347DLL.dll`.
- Do not use GitHub codeload auto-generated source zips as release asset URLs.
- Do not release based only on OpenOCD `verify OK`.

Allowed:

- Publish the source fork, patches, tags, and Windows binaries under GPL-2.0-or-later.
- Bundle only the minimum required runtimes whose license documents can be included, such as libusb, libhidapi, or libjaylink when needed.
- Keep `openwch/openocd_wch` binaries/configs locally as comparison, reproduction, and compatibility evidence.

## Release Asset Names

Recommended:

```text
openocd-wch-ch32v003-bootfix-<version>-windows-x86_64.zip
```

Avoid:

```text
openocd_wch-1.0.0.zip
openocd.zip
source.zip
```

Rationale:

- Avoid confusion with upstream distribution artifacts.
- Make host OS and architecture clear for Arduino Boards Manager and manual installation.
- Keep checksum, size, and release notes easy to pin.

## Open Questions

- The WCH-side download page or archive name for the "WCH official tarball" imported by `cjacker/wch-openocd`.
- The exact corresponding source for the `openwch/openocd_wch` 1.0.0 binary distribution.
- Redistribution terms for WCH proprietary DLLs.
- The minimum runtime DLL set required by the final build.

Open questions must be resolved through the checklist in `packaging/windows/README.md` before release.
