# Arduino Package Index Policy

## Goal

Make the CH32V003 BOOT-write-fixed OpenOCD package easy to consume from Arduino Boards Manager.

## Principles

- `url` must point to a fixed GitHub release asset zip.
- `archiveFileName` must match the asset filename.
- `checksum` must use the zip SHA-256.
- `size` must use the zip byte size.
- Do not use the codeload source zip from `openwch/openocd_wch`.
- Arduino package index entries must reference only hardware-verified release assets.

For the current Windows release, the only candidate asset is the `windows-x86` / `i686-mingw32` / WCHLinkDLL backend / WCH official driver stack asset. Do not add WinUSB/libusbK assets or unverified architecture assets to the package index.

## Tool Definition Draft

Values for the actual package index are fixed after the release asset is created.

```json
{
  "name": "openocd_wch",
  "version": "<version>",
  "systems": [
    {
      "host": "<arduino-host>",
      "archiveFileName": "openocd-wch-ch32v003-bootfix-<version>-windows-x86-wchdriver.zip",
      "url": "https://github.com/<owner>/<repo>/releases/download/<tag>/openocd-wch-ch32v003-bootfix-<version>-windows-x86-wchdriver.zip",
      "checksum": "SHA-256:<sha256>",
      "size": "<bytes>"
    }
  ]
}
```

Release asset values in the public repository are fixed after building from the public tag with GitHub Actions and passing the manual release gate. The following candidate values are for `v0.11.0-ch32v003bootfix.2`; `checksum` and `size` are filled only after downloading the release asset again after publication.

```json
{
  "name": "openocd_wch",
  "version": "0.11.0-ch32v003bootfix.2",
  "systems": [
    {
      "host": "i686-mingw32",
      "archiveFileName": "openocd-wch-ch32v003-bootfix-0.11.0-ch32v003bootfix.2-windows-x86-wchdriver.zip",
      "url": "https://github.com/lopple/openocd-wch-ch32v003-bootfix/releases/download/v0.11.0-ch32v003bootfix.2/openocd-wch-ch32v003-bootfix-0.11.0-ch32v003bootfix.2-windows-x86-wchdriver.zip",
      "checksum": "SHA-256:<sha256-after-public-release-download>",
      "size": "<bytes-after-public-release-download>"
    }
  ]
}
```

Confirm `host` against compatibility with the existing Arduino package index. Because this is a 32-bit executable, the candidate host is `i686-mingw32`. Only values that pass post-publication release asset download, SHA256/size recheck, targetless smoke test, write-plan trap, and hardware BOOT write/readback may be added to the Arduino package index.

## Notes

- Update the package index only after downloading the published release asset and fixing checksum/size.
- The checksum/size above are placeholders until the GitHub release asset is downloaded and rehashed after public release.
- Confirm `host` against the target Boards Manager environment and existing package index values before finalizing it.
- Do not reuse the same version when replacing an asset. Bump the version if replacement is required.
- Boards Manager users must be able to find the source repository from the release body and README.
