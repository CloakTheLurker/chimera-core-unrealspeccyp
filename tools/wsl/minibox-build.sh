#!/bin/sh
# Build miniBox host + guest toolchain (musl, emulibc, libstdc++). Resumable.
set -eu
. "$(dirname "$0")/env.sh"
$NINJA -C "$MB_BUILD"
$NINJA -C "$MB_BUILD" musl-gcc source/guest/emulibc.c.o source/guest/cxxglue.c.o libstdcxx-installed.stamp
