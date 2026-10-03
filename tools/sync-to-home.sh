#!/bin/sh
# sync-to-home.sh — edit in Chimera Dev, build from ~/ copies (cp -a).
#
#   ./tools/sync-to-home.sh
#
# Copies Chimera Dev/chimera -> ~/chimera and
# Chimera Dev/chimera-core-unrealspeccyp -> ~/chimera-core-unrealspeccyp,
# then checks MINIBOX_DIR=~/chimera/extern/chimera-common-minibox.
# .git is deliberately NOT synced: git objects are read-only, so a second
# cp -a over them fails with Permission denied; the ~/ copies are build
# trees, not repos (first seed copied .git once; history lives in
# Chimera Dev). Everything else goes over verbatim with cp -a.
# Run from anywhere; paths resolve from this script.
set -eu
HERE=$(dirname "$0")
DEV=$(cd "$HERE/../.." && pwd -P)
HOME_DIR="$HOME"

sync_tree() {
  SRC="$1"; DST="$2"
  echo "sync: $SRC -> $DST (cp -a, excluding .git)"
  mkdir -p "$DST"
  (cd "$SRC" && find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec cp -a {} "$DST/" \;)
}
sync_tree "$DEV/chimera" "$HOME_DIR/chimera"
sync_tree "$DEV/chimera-core-unrealspeccyp" "$HOME_DIR/chimera-core-unrealspeccyp"

MINIBOX_DIR="$HOME_DIR/chimera/extern/chimera-common-minibox"
if [ -f "$MINIBOX_DIR/meson.build" ]; then
  echo "sync: MINIBOX_DIR OK ($MINIBOX_DIR)"
else
  echo "sync: WARNING — MINIBOX_DIR missing: $MINIBOX_DIR" >&2
  echo "  (guest builds need it: extern/chimera-common-minibox submodule in ~/chimera)" >&2
fi
echo "sync: done. Build from the ~/ copies; edit in Chimera Dev."
