#!/bin/sh
# sync-to-home.sh — edit in Chimera Dev, build from ~/ copies (cp -a).
#
#   ./tools/sync-to-home.sh
#
# Copies Chimera Dev/chimera -> ~/chimera and
# Chimera Dev/chimera-core-unrealspeccyp -> ~/chimera-core-unrealspeccyp,
# then checks MINIBOX_DIR=~/chimera/extern/chimera-common-minibox.
# Run from anywhere; paths resolve from this script.
set -eu
HERE=$(dirname "$0")
DEV=$(cd "$HERE/../.." && pwd -P)
HOME_DIR="$HOME"
CORE_SRC="$DEV/chimera-core-unrealspeccyp"
CHIMERA_SRC="$DEV/chimera"

echo "sync: $CHIMERA_SRC -> $HOME_DIR/chimera"
mkdir -p "$HOME_DIR/chimera"
cp -a "$CHIMERA_SRC/." "$HOME_DIR/chimera/"
echo "sync: $CORE_SRC -> $HOME_DIR/chimera-core-unrealspeccyp"
mkdir -p "$HOME_DIR/chimera-core-unrealspeccyp"
cp -a "$CORE_SRC/." "$HOME_DIR/chimera-core-unrealspeccyp/"

MINIBOX_DIR="$HOME_DIR/chimera/extern/chimera-common-minibox"
if [ -f "$MINIBOX_DIR/meson.build" ]; then
  echo "sync: MINIBOX_DIR OK ($MINIBOX_DIR)"
else
  echo "sync: WARNING — MINIBOX_DIR missing: $MINIBOX_DIR" >&2
  echo "  (guest builds need it: extern/chimera-common-minibox submodule in ~/chimera)" >&2
fi
echo "sync: done. Build from the ~/ copies; edit in Chimera Dev."
