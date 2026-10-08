#!/bin/sh
# Apply the whole patches/series all-or-nothing (never one by one) onto a
# FRESH COPY of upstream, so extern/upstream stays pristine in git.
# Usage: apply-patches.sh <upstream-src> <patched-dst>
#
# Line endings: upstream ships CRLF sources; patches are authored LF.
# The files a patch touches are normalized to LF in the BUILD COPY ONLY
# (compilers do not care; both flavors compile the same copy, so parity
# is unaffected). Binary files (res/rom/*) are never touched.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
SERIES="$ROOT/patches/series"
SRC="${1:-$ROOT/extern/upstream}"
DST="${2:?usage: apply-patches.sh <upstream-src> <patched-dst>}"

if [ ! -d "$SRC/snapshot" ] || [ ! -f "$SRC/speccy.h" ]; then
  echo "apply-patches: refusing: $SRC does not look like UnrealSpeccyP (missing speccy.h/snapshot/)" >&2
  exit 1
fi
rm -rf "$DST"
mkdir -p "$(dirname "$DST")"
cp -a "$SRC" "$DST"
if [ ! -s "$SERIES" ] || ! grep -q -v '^#' "$SERIES"; then
  echo "apply-patches: series empty — using upstream verbatim."
  exit 0
fi
while read -r p rest; do
  case "$p" in ""|\#*) continue;; esac
  echo "apply-patches: $p"
  grep '^--- a/' "$ROOT/patches/$p" | sed 's|^--- a/||' | while read -r f; do
    if [ -f "$DST/$f" ]; then
      sed -i 's/\r$//' "$DST/$f"
    fi
  done
  patch -p1 --forward -d "$DST" < "$ROOT/patches/$p" || {
    echo "apply-patches: FAILED on $p" >&2
    exit 1
  }
done < "$SERIES"
echo "apply-patches: done ($DST)."
