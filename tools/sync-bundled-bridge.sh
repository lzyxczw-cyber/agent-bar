#!/usr/bin/env bash
# Copy the DSH bridge program into its runtime directory.
#
# Refreshes dsh-bridge.mjs, lib/, and vendor/. Copies README.md when the
# source has one. Dev-only bridge/tools stay behind.
#
# Runtime files already in the destination are left in place:
#   status.json, status.sock, audit.log, usage-state.json, control/
# and any other file that is not part of the program set above.
#
# Usage: sync-bundled-bridge.sh <source-bridge-dir> <dest-bridge-dir>
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: sync-bundled-bridge.sh <source-bridge-dir> <dest-bridge-dir>" >&2
  exit 2
fi

SRC=$1
DEST=$2

if [ ! -f "$SRC/dsh-bridge.mjs" ] || [ ! -d "$SRC/lib" ] || [ ! -d "$SRC/vendor" ]; then
  echo "bundled bridge is incomplete: $SRC" >&2
  exit 1
fi

src_real=$(cd "$SRC" && pwd -P)
mkdir -p "$DEST"
dest_real=$(cd "$DEST" && pwd -P)

# Literal prefix check. `case` would treat *, ?, and [ in a path as globs.
if [ "$dest_real" = "$src_real" ] || [ "${dest_real#"$src_real"/}" != "$dest_real" ]; then
  echo "refusing to sync bridge onto itself: $dest_real" >&2
  exit 1
fi
if [ "${src_real#"$dest_real"/}" != "$src_real" ]; then
  echo "refusing to sync a bridge directory into its own contents: $dest_real" >&2
  exit 1
fi

stage=$(mktemp -d "${TMPDIR:-/tmp}/agentbar-bridge-sync.XXXXXX")
trap 'rm -rf "$stage"' EXIT

# ditto copies a directory's contents into the destination (no lib/lib nesting).
# Linux hosts used for the sync tests do not have it, so cp -R of `dir/.` is
# the fallback. Both replace the program tree and leave sibling runtime files.
copy_dir() {
  local src=$1 dest=$2
  mkdir -p "$dest"
  if command -v ditto >/dev/null 2>&1; then
    ditto "$src" "$dest"
  else
    cp -R "$src/." "$dest/"
  fi
}

copy_dir "$SRC/lib" "$stage/lib"
copy_dir "$SRC/vendor" "$stage/vendor"
cp "$SRC/dsh-bridge.mjs" "$stage/dsh-bridge.mjs"
if [ -f "$SRC/README.md" ]; then
  cp "$SRC/README.md" "$stage/README.md"
fi

# A dirty checkout can contain generated files next to the program.
# They are not part of the bundle and must not replace a live runtime.
rm -f "$stage/status.json" "$stage/status.sock" "$stage/audit.log" "$stage/usage-state.json"
rm -rf "$stage/control" "$stage/tools"

rm -rf "$DEST/lib" "$DEST/vendor"
copy_dir "$stage/lib" "$DEST/lib"
copy_dir "$stage/vendor" "$DEST/vendor"
cp "$stage/dsh-bridge.mjs" "$DEST/dsh-bridge.mjs"
if [ -f "$stage/README.md" ]; then
  cp "$stage/README.md" "$DEST/README.md"
fi

# Files copied out of a downloaded app can carry the quarantine attribute.
# The bridge is data for the machine-local Node, so drop that attribute
# when the macOS tool is present. Linux test hosts do not have it.
if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$DEST/lib" "$DEST/vendor" "$DEST/dsh-bridge.mjs" >/dev/null 2>&1 || true
  if [ -f "$DEST/README.md" ]; then
    xattr -c "$DEST/README.md" >/dev/null 2>&1 || true
  fi
fi
