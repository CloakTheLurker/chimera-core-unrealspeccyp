#!/bin/sh
# Apply the whole patches/series all-or-nothing (never one by one) onto a
# FRESH COPY of upstream, so extern/upstream stays pristine in git.
# Usage: apply-patches.sh <upstream-src> <patched-dst>
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
  patch -p1 --forward -d "$DST" < "$ROOT/patches/$p" || {
    echo "apply-patches: FAILED on $p" >&2
    exit 1
  }
done < "$SERIES"
echo "apply-patches: done ($DST)."
