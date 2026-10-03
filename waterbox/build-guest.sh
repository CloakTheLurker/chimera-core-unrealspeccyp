#!/bin/sh
# build-guest.sh — M2: the emulator through the musl guest toolchain.
#
# Requires MINIBOX_DIR (the chimera-common-minibox checkout the core builds
# against). It is passed down from build-package.sh; this script stops with a
# message if it is absent. No $HOME guessing, no absolute paths in toolchain
# files — grep for $HOME before pushing.
set -eu
HERE=$(dirname "$0")

if [ -z "${MINIBOX_DIR:-}" ]; then
  echo "build-guest: MINIBOX_DIR is not set." >&2
  echo "  usage: MINIBOX_DIR=~/chimera/extern/chimera-common-minibox ./waterbox/build-guest.sh" >&2
  echo "  (build-package.sh passes it down from -r <chimera>; never guess it from \$HOME)" >&2
  exit 1
fi
if [ ! -f "$MINIBOX_DIR/meson.build" ]; then
  echo "build-guest: MINIBOX_DIR=$MINIBOX_DIR does not look like chimera-common-minibox (missing meson.build)" >&2
  exit 1
fi

"$HERE/apply-patches.sh"

echo "build-guest: MINIBOX_DIR=$MINIBOX_DIR"
echo "build-guest: M2 implements the guest meson wiring here:"
echo "  - waterbox-guest cross file from \$MINIBOX_DIR/source/guest/"
echo "  - fixed base 0x36f00000000 via linkscript.T"
echo "  - guest flags: -mcmodel=large -mno-red-zone -fno-pic -fno-pie"
echo "    -Dthread_local= -D_Thread_local= -D__thread= (no TLS; check-wbx.sh enforces)"
echo "  - weak symbols forced with -Wl,-u,<name>; musl open() O_CLOEXEC wrap;"
echo "    gaps collected in waterbox/guest-syscalls.cpp"
echo "build-guest: STUB — full wiring lands in M2 after the M1 time seam."
