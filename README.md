# gdio.rizin-bundle

Relocatable bundles of [rizin](https://rizin.re) and the [rz-ghidra](https://github.com/rizinorg/rz-ghidra) decompiler plugin
for **macOS (Apple Silicon and Intel)** and **Windows (x64)**. GameDriver Test Assistant runs `rizin` with the plugin's
`pdg` command to decompile the methods of an IL2CPP game (Method Insight); shipping the bundle with Test Assistant means
users do not have to install or build either tool.

This repository holds only the build scripts, the pinned versions and the releases. Nothing in it is GameDriver
product code, and no secrets or certificates are involved: **the bundles are not signed here**. Test Assistant's own
release process signs (and, on macOS, notarizes) everything in its publish folder, bundle included.

## What is in a release

Three zips and their SHA-256 files, one per runtime identifier:

```
gdio-rizin-bundle-rizin0.9.1-rzghidra0.9.0-r1-osx-arm64.zip   (+ .sha256)
gdio-rizin-bundle-rizin0.9.1-rzghidra0.9.0-r1-osx-x64.zip
gdio-rizin-bundle-rizin0.9.1-rzghidra0.9.0-r1-win-x64.zip
```

Each unpacks to one folder, `rizin/`:

| Path | What |
|---|---|
| `bin/rizin` (`rizin.exe`) | the only executable Test Assistant runs |
| `lib/` | rizin's libraries; the rz-ghidra plugins (`core_ghidra`, `asm_ghidra`, `analysis_ghidra`) are in the plugins folder below it |
| `<plugins>/rz_ghidra_sleigh/` | the Sleigh language data the decompiler needs (about 29 MB) |
| `share/rizin/` | rizin's data files |
| `licenses/` | the licence texts of rizin and rz-ghidra |
| `BUNDLE.json` | versions, the exact rz-ghidra commit, and where the plugins and Sleigh data are (`pluginsDirectory`, `sleighDirectory`) |

The bundle is **relocatable**: nothing in it refers to the folder it was built in. The build proves that by running the
decompiler on a known ARM64 function from a copy moved into a folder with a space in its path ("Application Support",
"Program Files").

## Using it

Run `bin/rizin` with two environment variables, exactly as Test Assistant does:

```
RZ_LIB_PLUGINS=<bundle>/<pluginsDirectory>
SLEIGHHOME=<bundle>/<sleighDirectory>
```

`SLEIGHHOME` matters: rz-ghidra compiles the absolute path of the folder it was built in as the default location of its
Sleigh data, so a plugin that has been moved finds no Sleigh specification and `pdg` prints nothing until it is set.

To fetch a released bundle (checks the SHA-256, unpacks to `<dest>/rizin`):

```
scripts/fetch-bundle.sh   --tag bundle-rizin0.9.1-rzghidra0.9.0-r1 --rid osx-arm64 --dest Publish/osx-arm64
scripts/fetch-bundle.ps1 -Tag bundle-rizin0.9.1-rzghidra0.9.0-r1 -Rid win-x64 -Dest Publish\win-x64
```

## Versions

`VERSIONS` pins everything: the rizin release (with the SHA-256 of the files downloaded), the rz-ghidra tag **and the
commit it must resolve to**, and a revision number. To move to new versions, edit `VERSIONS`, run the workflow, publish.
rz-ghidra must match rizin's version line (rz-ghidra 0.9.x with rizin 0.9.x).

## How it is built

The `build-bundle` workflow (Actions > build-bundle > Run workflow; tick *publish* to attach the zips to a release named
after `VERSIONS`) runs these scripts on a macOS Apple Silicon, a macOS Intel and a Windows runner. You can run them yourself:

- `scripts/build-macos.sh` (needs cmake, meson, ninja): builds **rizin from the pinned source** with
  `-Dportable=true -Dlocal=enabled -Duse_gpl=false` (relative paths, and without rizin's GPL-only code), then rz-ghidra
  against it, makes every Mach-O file refer to the others relatively and ad-hoc signs it again
  (`scripts/relocate_macos.py`), self-tests, and zips.
- `scripts/build-windows.ps1` (needs an MSVC environment, cmake, ninja): uses **rizin's own prebuilt Windows package**
  (checked against the pinned SHA-256), builds rz-ghidra from the pinned tag against it, self-tests, and zips.
- `scripts/selftest.sh` / `selftest.ps1`: the moved-folder decompile test both builds end with.

## Licences and source

| Component | Licence | Source |
|---|---|---|
| rizin | LGPL-3.0 (see below for GPL code) | https://github.com/rizinorg/rizin , the tag in `VERSIONS` |
| rz-ghidra | LGPL-3.0 | https://github.com/rizinorg/rz-ghidra , the tag and commit in `VERSIONS` |
| Ghidra decompiler and Sleigh specifications (inside rz-ghidra) | Apache-2.0 | rz-ghidra's `third-party` and `ghidra` folders at that commit |
| rizin's bundled libraries (capstone, zlib, and so on) | their own licences | rizin's `subprojects` at that tag |

The licence texts shipped with each bundle are in its `licenses/` folder. rizin builds some GPL-licensed code in by
default (`use_gpl`); the macOS bundles are built **without** it (`BUNDLE.json` says `"gplCodeIncluded": false`). The
Windows bundle uses rizin's own prebuilt package, which is rizin's default build.

**Source offer.** Every file in a bundle is built from the sources named above: the pinned upstream tags and commits, plus
the scripts in this repository, which anyone can run to reproduce the bundle. Anyone who received a bundle can get the
corresponding source by following those links, or by asking GameDriver at the address on https://gamedriver.io .

The build scripts and documentation in this repository are under the MIT licence (`LICENSE`); see
`THIRD_PARTY_NOTICES.md` for the software they build.
