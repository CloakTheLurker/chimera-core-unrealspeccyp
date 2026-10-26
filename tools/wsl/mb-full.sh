#!/bin/sh
# Full minibox toolchain in WSL-native space-free dirs (+ pollable log).
# Usage: mb-full.sh   (poll $MB_NATIVE/build/mb-full.log for TOOLCHAIN-DONE)
set -eu
. "$(dirname "$0")/env.sh"
sh "$(dirname "$0")/mb-sync.sh"
mkdir -p "$MB_BUILD"
LOG="$MB_NATIVE/mb-full.log"
{
  echo "mb-full: start $(date)"
  if [ ! -f "$MB_BUILD/build.ninja" ]; then
    $MESON setup "$MB_BUILD" "$MB_SRC" -Dguest_cpp=true
  fi
  $NINJA -C "$MB_BUILD"
  $NINJA -C "$MB_BUILD" musl-gcc source/guest/emulibc.c.o source/guest/cxxglue.c.o libstdcxx-installed.stamp
  echo "mb-full: TOOLCHAIN-DONE $(date)"
} > "$LOG" 2>&1
