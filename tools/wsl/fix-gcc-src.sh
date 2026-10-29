#!/bin/sh
# Repair a partial GCC source extraction (killed tar leaves src/ half-done
# while the guard skips re-extraction; a partial download corrupts the
# tarball too). Clears src+build ALWAYS, drops a bad tarball for re-fetch.
set -eu
. "$(dirname "$0")/env.sh"
D="$MB_BUILD/cpp-toolchain"
V=$(g++ -dumpfullversion)
echo "fix-gcc-src: clearing partial src + build trees..."
rm -rf "$D/src" "$D/build"
if [ -f "$D/gcc-$V.tar.xz" ]; then
  if tar tzf "$D/gcc-$V.tar.xz" > /dev/null 2>&1; then
    echo "fix-gcc-src: tarball OK, kept."
  else
    echo "fix-gcc-src: tarball corrupt — deleting, will re-fetch."
    rm -f "$D/gcc-$V.tar.xz"
  fi
else
  echo "fix-gcc-src: no tarball — will fetch."
fi
