# Manual Release Gate

This document defines the manual gate that must pass before publishing a Windows `windows-x86` / `i686-mingw32` / WCH official driver stack release.

GitHub Actions does not have real hardware attached. Therefore, CI targetless smoke tests are not enough to decide whether a release is publishable.

## Scope

This release line is fixed to the following scope:

- Package label: `windows-x86`
- Arduino host: `i686-mingw32`
- Backend: WCHLinkDLL backend
- Driver requirement: WCH official driver stack installed by WCH-LinkUtility or the WCH official driver package
- `WCHLinkDLL.dll` / `CH347DLL.dll`: not bundled in the release zip
- WinUSB/libusbK: out of scope

## Gate A: Candidate Check Before Tagging

Before creating a tag, check the target commit using a GitHub Actions artifact.

Use one of these candidate artifacts:

- The artifact from the `Windows x86 artifact` workflow
- A dry-run artifact from the `Windows release draft` workflow run with `workflow_dispatch`

The `workflow_dispatch` dry run does not create a release, so it is suitable for candidate checks before tagging. The artifact checked in Gate A/B must still come from the same head commit that will be tagged. If the tag target changes, the generated binary hash may also change, so Gate C must re-check the downloaded release asset.

1. The workflow that produced the candidate artifact succeeded.
2. The artifact zip and `.sha256.txt` were downloaded, and the sidecar hash matches the zip.
3. The zip contains:
   - `bin/openocd.exe`
   - `share/openocd/scripts/`
   - `scripts/`
   - `COPYING`
   - `LICENSES/`
   - `NOTICE.txt`
   - `SOURCE.txt`
   - `BUILDINFO.txt`
   - `DLL-IMPORTS.txt`
   - `SHA256SUMS.txt`
4. `DLL-IMPORTS.txt` contains only the expected Windows system DLL imports, such as:
   - `KERNEL32.dll`
   - `msvcrt.dll`
   - `USER32.dll`
   - `WS2_32.dll`
5. The zip does not bundle:
   - `WCHLinkDLL.dll`
   - `CH347DLL.dll`
   - `JLinkARM.dll`
   - `FTD2XX.dll`
6. The release text/import audit passed.

## Gate B: Hardware BOOT Write Check

The target is the CH32V003 family. If possible, repeat the check several times on CH32V003F4 hardware.

Prerequisites:

- Connect through WCH-LinkE or WCH-LinkRV.
- Windows has WCH-LinkUtility or the WCH official driver stack installed.
- Do not replace the driver with Zadig, WinUSB, or libusbK.
- USER flash contains a known firmware or known pattern.
- A known bootloader image is prepared for the BOOT area.

Required records:

- source commit
- workflow run URL
- Artifact name
- zip filename
- zip SHA256
- zip size
- `openocd.exe --version`
- target chip/package
- WCH-Link model
- Driver stack assumption
- BOOT image SHA256
- USER flash pre-write hash
- BOOT flash pre-write hash

Pre-write checks:

1. Use `wlink_write_plan_trap` or an equivalent preflight to confirm that the BOOT write plan stays within `0x1ffff000..0x1ffff77f`.
2. Confirm that USER flash and BOOT flash are handled as separate flash banks.
3. Confirm that the erase range is not translated to the beginning of USER flash.

Success criteria:

1. The post-write BOOT readback hash matches the input image.
2. USER flash full/head hashes match before and after the write.
3. OpenOCD verify does not contradict independent readback/hash evidence.
4. The beginning of USER flash is not corrupted.
5. If needed, compare against WCH-LinkUtility readback and confirm that there are no unexpected differences.

On failure:

- Do not create a release tag.
- If a draft release already exists, do not publish it.
- If flash protection settings were changed, record the exact operation in the gate log.
- If WCH-LinkUtility was used for recovery, record the recovery procedure and readback/hash results.

## Gate C: Draft Release Asset Check

After tag push, the `Windows release draft` workflow creates a draft prerelease and uploads the release asset.

Before publishing the draft release:

1. Download the release asset zip from GitHub Releases.
2. Record the downloaded zip SHA256 and byte size.
3. Confirm that the release asset `.sha256.txt` matches the downloaded zip hash.
4. Re-run the same internal zip audit from Gate A on the downloaded release asset.
5. Re-run the hardware check from Gate B using `openocd.exe` from the downloaded release asset.

Only the URL, SHA256, and byte size from this downloaded release asset may be used in an Arduino package index.

## Tag and Release Order

Recommended order:

1. Build an artifact for the candidate commit with the `Windows x86 artifact` workflow.
2. Pass Gate A.
3. Pass Gate B with the candidate artifact.
4. Save the gate record as Markdown.
5. Create an annotated tag on the target commit.
6. Push the tag.
7. Let the `Windows release draft` workflow create the draft prerelease.
8. Pass Gate C with the downloaded release asset.
9. Add the Gate B/C hashes and known limitations to the draft release body.
10. Publish the draft release.
11. Download the release asset again and confirm hash/size.
12. Update the Arduino package index candidate values.

## Gate Record Template

```markdown
# Release gate <tag>

Date:
Operator:

## Source

- Repository:
- Commit:
- Tag:
- Workflow run:
- Artifact:

## Asset

- Filename:
- Size:
- SHA256:
- openocd.exe version:
- openocd.exe SHA256:

## Hardware

- Target:
- WCH-Link:
- Driver stack:
- Connection:

## Hashes

- BOOT image SHA256:
- USER pre full/head SHA256:
- BOOT pre SHA256:
- BOOT post SHA256:
- USER post full/head SHA256:

## Preflight

- BOOT write address range:
- USER bank:
- BOOT bank:
- erase range:

## Result

- BOOT readback matches:
- USER hash unchanged:
- OpenOCD verify vs readback:
- WCH-LinkUtility comparison:

## Notes
```
