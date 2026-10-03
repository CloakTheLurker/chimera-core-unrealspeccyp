#!/bin/sh
# build-native.sh — M0: headless native build, no frontend, no window system.
#
# Compiles upstream core sources (root *.cpp, z80/, tools/, snapshot/,
# devices/..., 3rdparty/minizip, 3rdparty/tinyxml2, vendored 3rdparty/zlib
# when the host has none — mirroring build/cmake/CMakeLists.txt)
# plus platform/platform.cpp, platform/io.cpp, platform/linux/io_select_linux.cpp (POSIX MkDir/FileSelect), and the waterbox/ adapter +
# run-native.cpp harness — with USE_BENCHMARK semantics: no USE_SDL /
# USE_SDL2 / USE_WXWIDGETS / USE_GL / USE_OAL / USE_UI / USE_CURL / USE_WEB.
# No SDL/GL/window linkage allowed in the output.
# C files go through $CC, C++ through $CXX (zlib is not C++-clean).
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
U="$ROOT/extern/upstream"
OUT="$ROOT/build/native"
OBJ="$OUT/obj"
mkdir -p "$OUT" "$OBJ"
rm -f "$OBJ"/*.o

"$HERE/apply-patches.sh"

CXX=${CXX:-g++}
CC=${CC:-gcc}
# M0 source list mirrors the usp build/cmake core globs minus every UI/platform.
# (Kept as a shell glob list, not cmake, so the headless constraint is visible.)
CXXSRCS=""
for d in "" z80 tools snapshot devices devices/fdd devices/input devices/sound; do
  for f in "$U/$d"/*.cpp; do
    [ -f "$f" ] && CXXSRCS="$CXXSRCS $f"
  done
done
CXXSRCS="$CXXSRCS $U/3rdparty/tinyxml2/tinyxml2.cpp"
CXXSRCS="$CXXSRCS $HERE/machine.cpp $HERE/run-native.cpp"
CSRCS="$U/3rdparty/minizip/ioapi.c $U/3rdparty/minizip/unzip.c"
CFLAGS_ZLIB=""
if [ -f /usr/include/zlib.h ]; then
  echo "build-native: system zlib found."
else
  echo "build-native: no system zlib — using vendored 3rdparty/zlib (as upstream cmake does)."
  for f in "$U"/3rdparty/zlib/*.c; do CSRCS="$CSRCS $f"; done
  CFLAGS_ZLIB="-I$U/3rdparty/zlib"
fi
INCS="-I$U -I$U/3rdparty/minizip -I$U/3rdparty/tinyxml2 $CFLAGS_ZLIB"

echo "build-native: compiling C++ (M0 headless reference)..."
# shellcheck disable=SC2086
n=0
for f in $CXXSRCS "$U/platform/platform.cpp" "$U/platform/io.cpp" "$U/platform/linux/io_select_linux.cpp"; do
  n=$((n+1))
  $CXX -std=gnu++11 -O2 -DUSE_BENCHMARK -D_POSIX $INCS -c "$f" -o "$OBJ/cxx_$n.o"
done
echo "build-native: compiling C..."
for f in $CSRCS; do
  n=$((n+1))
  $CC -O2 -D_POSIX $INCS -c "$f" -o "$OBJ/c_$n.o"
done
echo "build-native: linking..."
$CXX "$OBJ"/*.o -o "$OUT/run-native" ${LDFLAGS:-}
echo "build-native: $OUT/run-native"
if command -v ldd >/dev/null 2>&1; then
  if ldd "$OUT/run-native" 2>/dev/null | grep -i -E 'SDL|libGL|openal|wx' ; then
    echo "build-native: FAILED — window-system linkage leaked in (see above)" >&2
    exit 1
  fi
fi
"$OUT/run-native" --help
