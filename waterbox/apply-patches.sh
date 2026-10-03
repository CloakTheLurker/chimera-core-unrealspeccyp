#!/bin/sh
# Apply the whole patches/series all-or-nothing (never one by one).
set -eu
HERE=$(dirname "$0")
ROOT="$HERE/.."
UPSTREAM="$ROOT/extern/upstream"
SERIES="$ROOT/patches/series"

if [ ! -d "$UPSTREAM/snapshot" ] || [ ! -f "$UPSTREAM/speccy.h" ]; then
  echo "apply-patches: refusing: $UPSTREAM does not look like UnrealSpeccyP (missing speccy.h/snapshot/)" >&2
  exit 1
fi
if [ -d "$UPSTREAM/.git" ]; then
  TOP=$(git -C "$UPSTREAM" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$TOP" ] && [ "$TOP" != "$(cd "$UPSTREAM" && pwd -P)" ]; then
    echo "apply-patches: refusing: $UPSTREAM resolves into another repo ($TOP)" >&2
    exit 1
  fi
  if [ -n "$(git -C "$UPSTREAM" status --porcelain)" ]; then
    echo "apply-patches: tree already patched (dirty) — leaving as-is."
    exit 0
  fi
fi
if [ ! -s "$SERIES" ] || ! grep -q -v '^#' "$SERIES"; then
  echo "apply-patches: series empty — nothing to do (M0 needs no patches)."
  exit 0
fi
while read -r p rest; do
  case "$p" in ""|\#*) continue;; esac
  echo "apply-patches: $p"
  patch -p1 -d "$UPSTREAM" < "$ROOT/patches/$p"
done < "$SERIES"
echo "apply-patches: done."
