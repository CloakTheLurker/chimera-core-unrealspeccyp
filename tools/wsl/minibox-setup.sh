#!/bin/sh
# One-time: meson setup of miniBox with the C++ guest toolchain.
set -eu
. "$(dirname "$0")/env.sh"
$MESON setup "$MB_BUILD" "$MINIBOX" -Dguest_cpp=true
