# Third-party software in the bundles

The bundles contain software that is not ours and is distributed under its own licences. The licence texts are in each
bundle's `licenses/` folder.

- **rizin** (https://github.com/rizinorg/rizin), LGPL-3.0, with its bundled libraries under their own licences (listed in
  rizin's `subprojects`). The macOS bundles are built with `-Duse_gpl=false`, leaving out rizin's GPL-only code; the
  Windows bundle uses rizin's own prebuilt package.
- **rz-ghidra** (https://github.com/rizinorg/rz-ghidra), LGPL-3.0.
- **Ghidra decompiler and Sleigh language specifications** (https://github.com/NationalSecurityAgency/ghidra, as embedded
  in rz-ghidra), Apache-2.0.

The pinned versions and commits are in `VERSIONS` and in each bundle's `BUNDLE.json`.
