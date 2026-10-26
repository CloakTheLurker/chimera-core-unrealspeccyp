#!/bin/sh
# WSL legs for the gate: build run-wbx (host driver) and run it.
# Usage: guest-legs.sh <frames> [extra run-wbx args...]
# Prints run-wbx summary lines to stdout for the gate to parse.
set -eu
. "$(dirname "$0")/env.sh"
FRAMES=${1:-600}
shift || true
GUEST_DIR="$WIN_CORE/build/guest"
MB_HOST_INC="$MB_SRC/source/host"
MB_HOST_LIB="$MB_BUILD/source/host"
gcc -O2 -I"$MB_HOST_INC" -I"$WIN_CORE/waterbox" \
  "$WIN_CORE/waterbox/run-wbx.c" -o "$GUEST_DIR/run-wbx" \
  -L"$MB_HOST_LIB" -lminiboxhost "-Wl,-rpath,$MB_HOST_LIB"
"$GUEST_DIR/run-wbx" --frames "$FRAMES" "$@" "$GUEST_DIR/core.wbx"
