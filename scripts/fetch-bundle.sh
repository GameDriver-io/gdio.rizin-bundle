#!/usr/bin/env bash
# Downloads one released bundle, checks its SHA-256, and unpacks it (the folder it creates is named "rizin").
# usage: fetch-bundle.sh --tag <release tag> --rid <osx-arm64|osx-x64|win-x64> --dest <folder>
#   e.g. fetch-bundle.sh --tag bundle-rizin0.9.1-rzghidra0.9.0-r1 --rid osx-arm64 --dest Publish/osx-arm64
# The asset name is derived from the tag: gdio-rizin-bundle-rizin<..>-rzghidra<..>-r<n>-<rid>.zip
set -euo pipefail
TAG=""; RID=""; DEST=""
while [ $# -gt 0 ]; do case "$1" in --tag) TAG="$2"; shift 2;; --rid) RID="$2"; shift 2;; --dest) DEST="$2"; shift 2;; *) echo "unknown argument $1" >&2; exit 2;; esac; done
[ -n "$TAG" ] && [ -n "$RID" ] && [ -n "$DEST" ] || { echo "usage: $0 --tag T --rid R --dest D" >&2; exit 2; }

NAME="gdio-rizin-bundle-${TAG#bundle-}-${RID}"
BASE="https://github.com/GameDriver-io/gdio.rizin-bundle/releases/download/$TAG"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/$NAME.zip" "$BASE/$NAME.zip"
curl -fsSL -o "$TMP/$NAME.zip.sha256" "$BASE/$NAME.zip.sha256"
( cd "$TMP" && shasum -a 256 -c "$NAME.zip.sha256" )
mkdir -p "$DEST"
rm -rf "$DEST/rizin"
unzip -q "$TMP/$NAME.zip" -d "$DEST"
echo "unpacked $NAME into $DEST/rizin"
