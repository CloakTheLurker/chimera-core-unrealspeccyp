#!/bin/sh
# Pre-fetch the GCC tarball the guest libstdc++ needs, verified with tar tJf.
# The miniBox script skips its own fetch when the file exists.
set -eu
. "$(dirname "$0")/env.sh"
D="$MB_BUILD/cpp-toolchain"
V=$(g++ -dumpfullversion)
mkdir -p "$D"
if [ -f "$D/gcc-$V.tar.xz" ] && tar tJf "$D/gcc-$V.tar.xz" > /dev/null 2>&1; then
  echo "fetch-gcc: tarball present and valid."
  exit 0
fi
rm -f "$D/gcc-$V.tar.xz"
for U in "https://mirrors.kernel.org/gnu/gcc/gcc-$V/gcc-$V.tar.xz" "https://ftpmirror.gnu.org/gcc/gcc-$V/gcc-$V.tar.xz" "https://gcc.gnu.org/pub/gcc/releases/gcc-$V/gcc-$V.tar.xz" "https://ftp.gnu.org/gnu/gcc/gcc-$V/gcc-$V.tar.xz"; do
  echo "fetch-gcc: trying $U"
  if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 25 -o "$D/gcc-$V.tar.xz.part" "$U"; then
    mv "$D/gcc-$V.tar.xz.part" "$D/gcc-$V.tar.xz"
    break
  fi
done
tar tJf "$D/gcc-$V.tar.xz" > /dev/null && echo "fetch-gcc: valid $D/gcc-$V.tar.xz"
