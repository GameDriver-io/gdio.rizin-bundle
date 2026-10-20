#!/usr/bin/env bash
# Builds the rizin + rz-ghidra bundle for the architecture of the Mac it runs on (osx-arm64 or osx-x64).
# rizin is built from the pinned source with -Dportable=true (relative paths), without its GPL-only code
# (-Duse_gpl=false); rz-ghidra is built from the pinned tag against it; the result is made relocatable, self-tested
# from a moved folder with a space in its path, and zipped.
# Needs: cmake, meson, ninja, git, curl, python3, Xcode command line tools.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/VERSIONS"

case "$(uname -m)" in arm64) RID=osx-arm64;; x86_64) RID=osx-x64;; *) echo "unsupported architecture $(uname -m)" >&2; exit 1;; esac
ARCH="$(uname -m)"
WORK="${WORK:-$HERE/work/$RID}"
STAGE="$WORK/stage/rizin"
OUT="${OUT:-$HERE/dist}"
NAME="gdio-rizin-bundle-rizin${RIZIN_VERSION}-rzghidra${RZ_GHIDRA_VERSION}-r${BUNDLE_REVISION}-${RID}"
JOBS="$(sysctl -n hw.ncpu)"

for tool in cmake meson ninja git curl python3 shasum zip; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done
rm -rf "$WORK"; mkdir -p "$WORK" "$STAGE" "$OUT"

echo "== rizin $RIZIN_VERSION ($RID)"
curl -fsSL -o "$WORK/rizin-src.tar.xz" "$RIZIN_SRC_URL"
echo "$RIZIN_SRC_SHA256  $WORK/rizin-src.tar.xz" | shasum -a 256 -c -
TOP="$(tar -tf "$WORK/rizin-src.tar.xz" | head -1 | cut -d/ -f1)"
tar -xf "$WORK/rizin-src.tar.xz" -C "$WORK"
RIZIN_SRC="$WORK/$TOP"
meson setup "$WORK/rizin-build" "$RIZIN_SRC" --prefix="$STAGE" --libdir=lib --buildtype=release \
  -Dportable=true -Dlocal=enabled -Duse_gpl=false -Dinstall_sigdb=false
ninja -C "$WORK/rizin-build" -j "$JOBS"
ninja -C "$WORK/rizin-build" install

echo "== rz-ghidra $RZ_GHIDRA_TAG"
git clone --quiet --depth 1 --branch "$RZ_GHIDRA_TAG" --recurse-submodules --shallow-submodules https://github.com/rizinorg/rz-ghidra "$WORK/rz-ghidra"
[ "$(git -C "$WORK/rz-ghidra" rev-parse HEAD)" = "$RZ_GHIDRA_COMMIT" ] || { echo "rz-ghidra $RZ_GHIDRA_TAG is not commit $RZ_GHIDRA_COMMIT" >&2; exit 1; }
cmake -S "$WORK/rz-ghidra" -B "$WORK/rz-ghidra-build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$STAGE" -DCMAKE_INSTALL_PREFIX="$STAGE" -DCMAKE_OSX_ARCHITECTURES="$ARCH"
cmake --build "$WORK/rz-ghidra-build" -j "$JOBS"
cmake --install "$WORK/rz-ghidra-build"

echo "== trimming to what Test Assistant runs"
rm -rf "$STAGE/include" "$STAGE/lib/pkgconfig" "$STAGE/lib/cmake" "$STAGE/share/man" "$STAGE/share/doc" "$STAGE"/lib/*.a
find "$STAGE/bin" -mindepth 1 -maxdepth 1 ! -name rizin -exec rm -rf {} +

echo "== licences and manifest"
mkdir -p "$STAGE/licenses"
for src in "$RIZIN_SRC" "$WORK/rz-ghidra"; do
  for f in "$src"/COPYING* "$src"/LICENSE* "$src"/NOTICE*; do
    [ -f "$f" ] && cp "$f" "$STAGE/licenses/$(basename "$src")-$(basename "$f")"
  done
done
PLUGIN_FILE="$(find "$STAGE" -name 'core_ghidra.*' | head -1)"
PLUGINS_REL="$(python3 -c "import os,sys; print(os.path.relpath(os.path.dirname(sys.argv[1]), sys.argv[2]))" "$PLUGIN_FILE" "$STAGE")"
cat > "$STAGE/BUNDLE.json" <<JSON
{
  "name": "$NAME",
  "rid": "$RID",
  "rizin": "$RIZIN_VERSION",
  "rzGhidra": "$RZ_GHIDRA_VERSION",
  "rzGhidraCommit": "$RZ_GHIDRA_COMMIT",
  "rizinExecutable": "bin/rizin",
  "pluginsDirectory": "$PLUGINS_REL",
  "sleighDirectory": "$PLUGINS_REL/rz_ghidra_sleigh",
  "gplCodeIncluded": false,
  "source": "https://github.com/GameDriver-io/gdio.rizin-bundle"
}
JSON

echo "== making it relocatable"
python3 "$HERE/scripts/relocate_macos.py" "$STAGE"

echo "== self-test (moved folder, path with a space)"
"$HERE/scripts/selftest.sh" "$STAGE" "$RIZIN_VERSION"

echo "== zip"
rm -f "$OUT/$NAME.zip"
( cd "$(dirname "$STAGE")" && zip -qry "$OUT/$NAME.zip" rizin )
( cd "$OUT" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256" )
echo "built $OUT/$NAME.zip ($(du -h "$OUT/$NAME.zip" | cut -f1))"

echo "== self-test of the unzipped result"
CHECK="$(mktemp -d)"; unzip -q "$OUT/$NAME.zip" -d "$CHECK"
"$HERE/scripts/selftest.sh" "$CHECK/rizin" "$RIZIN_VERSION"
rm -rf "$CHECK"
