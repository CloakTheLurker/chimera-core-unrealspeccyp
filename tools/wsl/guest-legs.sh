#!/bin/sh
# WSL legs for the M2 gate: build run-wbx (host driver) and run the parity
# vector. Prints run-wbx summary lines to stdout for the gate to parse.
# Usage: guest-legs.sh <frames>
set -eu
. "$(dirname "$0")/env.sh"
export MESON="python3 $HOME/tools/meson-1.7.0/meson.py"
export NINJA="$HOME/.local/bin/ninja"
FRAMES=${1:-600}
GUEST_DIR="$WIN_CORE/build/guest"
MB_HOST_INC="$MINIBOX/source/host"
MB_HOST_LIB="$MB_BUILD/source/host"
gcc -O2 -I"$MB_HOST_INC" -I"$WIN_CORE/waterbox" \
  "$WIN_CORE/waterbox/run-wbx.c" -o "$GUEST_DIR/run-wbx" \
  -L"$MB_HOST_LIB" -lminiboxhost "-Wl,-rpath,$MB_HOST_LIB"
"$GUEST_DIR/run-wbx" --frames "$FRAMES" "$GUEST_DIR/core.wbx"
