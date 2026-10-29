#!/bin/sh
# Stage 1: meson setup (if needed) + host build. Fast; run in foreground.
set -eu
. "$(dirname "$0")/env.sh"
if [ ! -f "$MB_BUILD/build.ninja" ]; then
  $MESON setup "$MB_BUILD" "$MB_SRC" -Dguest_cpp=true
fi
$NINJA -C "$MB_BUILD"
echo "mb-stage1: HOST-DONE"
