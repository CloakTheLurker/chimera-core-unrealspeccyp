#!/bin/sh
# Build miniBox host + guest toolchain (musl, emulibc, libstdc++). Resumable.
set -eu
. "$(dirname "$0")/env.sh"
$HOME/.local/bin/ninja -C "$MB_BUILD"
