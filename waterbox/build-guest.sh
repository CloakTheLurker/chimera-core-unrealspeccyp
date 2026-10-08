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
# ~/chimera and is shared by path translation below).
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
if [ "$(uname -s)" = "Linux" ]; then
  sh "$HERE/guest-link.sh" "$ROOT" "$MINIBOX_DIR" "$OUT"
else
  if ! command -v wsl.exe >/dev/null 2>&1; then
    echo "build-guest: guest link needs Linux (or WSL with Ubuntu); neither found" >&2
    exit 1
  fi
  export MSYS_NO_PATHCONV=1
  # msys /home/admin/X == C:\Users\admin\X == WSL /mnt/c/Users/admin/X.
  WSLROOT=$(cd "$ROOT" && pwd -W | tr "\134" "/" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
  # Kill-after-grace + retries: the 9P session teardown stalls
  # intermittently (a fresh WSL exits in ~2 min; a wedged one never does).
  # Cap is 25 min (a healthy from-scratch link needs ~15); guest-link.sh is
  # resumable and objects land atomically, so a retry continues where the
  # kill left it. A retry first terminates Ubuntu to unwedge the session
  # (other distros are left alone).
  attempt=0
  while [ $attempt -lt 3 ]; do
    attempt=$((attempt+1))
    if timeout -k 60 1500 wsl.exe -d Ubuntu -- sh "$WSLROOT/tools/wsl/guest-build.sh" < /dev/null; then
      break
    fi
    echo "build-guest: WSL attempt $attempt failed — terminating Ubuntu and retrying" >&2
    wsl.exe -t Ubuntu 2>/dev/null || true
    sleep 10
    if [ $attempt -ge 3 ]; then
      echo "build-guest: WSL failed 3 times" >&2
      exit 1
    fi
  done
fi
echo "build-guest: $OUT/core.wbx"
