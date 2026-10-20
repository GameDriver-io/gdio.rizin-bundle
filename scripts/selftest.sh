#!/usr/bin/env bash
# Proves a staged bundle works AFTER being moved to a different folder (with a space in its path, like
# "Application Support" or "Program Files"): runs the decompiler on a known ARM64 function the way Test Assistant
# does (RZ_LIB_PLUGINS + SLEIGHHOME, never the baked-in build paths).
# usage: selftest.sh <bundle root: the folder that contains bin/ and lib/> <expected rizin version>
set -euo pipefail
SRC="$1"; EXPECTED="$2"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
DEST="$TMP/moved bundle/rizin"
mkdir -p "$DEST"; cp -R "$SRC/." "$DEST/"

PLUGINS="$(dirname "$(find "$DEST" -name 'core_ghidra.*' -not -name '*.a' | head -1)")"
[ -d "$PLUGINS" ] || { echo "SELFTEST FAILED: no core_ghidra plugin in the bundle" >&2; exit 1; }
SLEIGH="$PLUGINS/rz_ghidra_sleigh"
[ -d "$SLEIGH" ] || { echo "SELFTEST FAILED: no rz_ghidra_sleigh folder next to the plugin" >&2; exit 1; }
RIZIN="$DEST/bin/rizin"

echo "rizin: $("$RIZIN" -v | head -1)"
"$RIZIN" -v | head -1 | grep -q "$EXPECTED" || { echo "SELFTEST FAILED: expected rizin $EXPECTED" >&2; exit 1; }

# ldr x0, [x0, #0xe0] ; ret   mapped at 0x4000
OUT="$(RZ_LIB_PLUGINS="$PLUGINS" SLEIGHHOME="$SLEIGH" "$RIZIN" -N -q -a arm -b 64 -e scr.color=0 -e analysis.in=io.maps -m 0x4000 \
  -c "wx 007040f9c0035fd6 @ 0x4000; s 0x4000; af; pdg" malloc://64 2>&1 || true)"
echo "$OUT"
echo "$OUT" | grep -q "0xe0"   || { echo "SELFTEST FAILED: the decompiled output does not contain the expected offset 0xe0" >&2; exit 1; }
echo "$OUT" | grep -q "return" || { echo "SELFTEST FAILED: the decompiled output has no return statement" >&2; exit 1; }
echo "$OUT" | grep -qi "no sleigh specification" && { echo "SELFTEST FAILED: the plugin could not find its Sleigh data" >&2; exit 1; }
echo "SELFTEST OK ($PLUGINS)"
