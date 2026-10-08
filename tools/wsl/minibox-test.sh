#!/bin/sh
# Build everything tests need (incl. non-default guest toolchain) and run
# the miniBox suite: host unit tests + conformance/thread/cpp guests.
set -eu
. "$(dirname "$0")/env.sh"
$MESON test -C "$MB_BUILD"
