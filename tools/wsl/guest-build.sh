#!/bin/sh
# WSL leg of build-guest.sh: paths are fixed translations of the ~/ trees.
set -eu
. "$(dirname "$0")/env.sh"
export MESON="python3 $HOME/tools/meson-1.7.0/meson.py"
export NINJA="$HOME/.local/bin/ninja"
sh "$WIN_CORE/waterbox/guest-link.sh" "$WIN_CORE" "$MINIBOX" "$WIN_CORE/build/guest"
