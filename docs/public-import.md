# Public Fresh Import Policy

This repository starts with a fresh public Git history.

The initial import contains the OpenOCD source tree, CH32V003 BOOT write fixes,
release automation, packaging policy, and source provenance notes needed for
public distribution.

The following private workbench material is intentionally not imported:

- local investigation reports
- hardware readback dumps
- bootloader test images
- build outputs
- release evidence captured from a private repository
- local machine paths

After the public repository is created, the public repository and its tags are
the source of record for release assets and Arduino package index metadata.
Checksums and byte sizes must be produced from public release assets, not from
private prerelease artifacts.
