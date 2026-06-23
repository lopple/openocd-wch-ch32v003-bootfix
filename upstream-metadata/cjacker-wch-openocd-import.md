# cjacker/wch-openocd import note

Date: 2026-06-22

This hard fork imports `cjacker/wch-openocd` as the maintainable source base for CH32V003 BOOT/system flash write fixes.

## Source

- Remote: <https://github.com/cjacker/wch-openocd.git>
- Branch: `main`
- Imported commit: `2b6802dde74a9560bdfb6eeecb6aff8a13cf8139`
- Upstream note: "Latest source of official WCH OpenOCD (2024-11-26 version)"

## Merge policy

- The public repository starts from a fresh import and does not include local investigation/report history.
- `README.md` is the project-facing hard fork README.
- The upstream README content was preserved under the `Source Base` section of `README.md`.
- OpenOCD generated-file ignore rules and release build output ignore rules are combined in `.gitignore`.

## Immediate focus

- `src/flash/nor/wchriscv.c`
- `src/jtag/drivers/wlinke.c`
- `tcl/target/wch-riscv.cfg`

The first bug-fix work should split CH32V003 USER flash `0x08000000` and BOOT/system flash `0x1ffff000` handling, then verify erase/write/readback paths independently of OpenOCD `verify OK`.
