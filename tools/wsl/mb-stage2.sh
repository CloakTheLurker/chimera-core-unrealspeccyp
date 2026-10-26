#!/bin/sh
# Stage 2: guest toolchain (musl-gcc, emulibc, cxxglue, libstdc++). Slow (~10+ min first time); resumable.
set -eu
. "$(dirname "$0")/env.sh"
$NINJA -C "$MB_BUILD" musl-gcc source/guest/emulibc.c.o source/guest/cxxglue.c.o libstdcxx-installed.stamp
echo "mb-stage2: TOOLCHAIN-DONE"
