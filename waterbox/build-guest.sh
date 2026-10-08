#!/bin/sh
# build-guest.sh — the emulator through the musl guest toolchain into core.wbx.
#
# Requires MINIBOX_DIR (the chimera-common-minibox checkout the core builds
# against). It is passed down from build-package.sh (-r <chimera>); this
# script stops with a message if it is absent. No $HOME guessing, no absolute
# paths in toolchain files — grep for $HOME before pushing.
#
# The guest is an ELF x86-64 for the sandbox's fake machine, so the link runs
# on Linux: natively there, or inside WSL Ubuntu from a Windows checkout
# (tools/wsl/guest-build.sh; the miniBox build itself already lives in
# ~/chimera and is shared by path translation below). The WSL call goes
# through wsl-call.sh (launch-and-poll): wsl.exe intermittently never exits
# after its script finishes, so the gate proceeds on a log marker and kills
# the hung client instead of waiting on it.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)

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

OUT="$ROOT/build/guest"
mkdir -p "$OUT"
if [ "$(uname -s)" = "Linux" ]; then
  sh "$HERE/guest-link.sh" "$ROOT" "$MINIBOX_DIR" "$OUT" > "$OUT/guest-build.log" 2>&1
  tail -n 3 "$OUT/guest-build.log"
else
  if ! command -v wsl.exe >/dev/null 2>&1; then
    echo "build-guest: guest link needs Linux (or WSL with Ubuntu); neither found" >&2
    exit 1
  fi
  # msys /home/admin/X == C:\Users\admin\X == WSL /mnt/c/Users/admin/X.
  WSLROOT=$(cd "$ROOT" && pwd -W | tr "\134" "/" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
  . "$HERE/wsl-call.sh"
  wsl_call guest-build.sh "" "guest-link: .* done" "$OUT/guest-build.log" 1500
fi
echo "build-guest: $OUT/core.wbx"
