#!/bin/sh
# build-native.sh — M0: headless native build, no frontend, no window system.
#
# Compiles upstream core sources (root *.cpp, z80/, tools/, snapshot/,
# devices/..., 3rdparty/minizip, 3rdparty/tinyxml2, vendored 3rdparty/zlib
# when the host has none — mirroring build/cmake/CMakeLists.txt)
# plus platform/platform.cpp, platform/io.cpp, platform/linux/io_select_linux.cpp
# (POSIX MkDir/FileSelect), and the waterbox/ adapter + run-native.cpp
# harness — with USE_BENCHMARK semantics: no USE_SDL / USE_SDL2 /
# USE_WXWIDGETS / USE_GL / USE_OAL / USE_UI / USE_CURL / USE_WEB.
# No SDL/GL/window linkage allowed in the output.
# C files go through $CC, C++ through $CXX (zlib is not C++-clean).
#
# Quoting: every path expansion is quoted (the tree lives under
# "Chimera Dev" — spaces are load-bearing). No space-joined file lists;
# each TU compiles inside its own glob loop; "$@" carries -I flags.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
U="$ROOT/extern/upstream"
OUT="$ROOT/build/native"
UP="$ROOT/build/upstream-patched"
OBJ="$OUT/obj"
mkdir -p "$OUT" "$OBJ"
rm -f "$OBJ"/*.o

"$HERE/apply-patches.sh" "$U" "$UP"

CXX=${CXX:-g++}
CC=${CC:-gcc}
ZLIB_SRCS=""
if [ -f /usr/include/zlib.h ]; then
  echo "build-native: system zlib found."
else
  echo "build-native: no system zlib — using vendored 3rdparty/zlib (as upstream cmake does)."
  ZLIB_SRCS="$UP/3rdparty/zlib"
fi

echo "build-native: compiling C++ (M0 headless reference)..."
n=0
# M0 source list mirrors the usp build/cmake core globs minus every UI/platform.
for d in "" z80 tools snapshot devices devices/fdd devices/input devices/sound; do
  for f in "$UP/$d/"*.cpp; do
    [ -f "$f" ] || continue
    n=$((n+1))
    "$CXX" -std=gnu++11 -O2 -DUSE_BENCHMARK -D_POSIX \
      -I"$UP" -I"$UP/3rdparty/minizip" -I"$UP/3rdparty/tinyxml2" \
      -c "$f" -o "$OBJ/cxx_$n.o"
  done
done
for f in "$UP/3rdparty/tinyxml2/tinyxml2.cpp" "$UP/platform/platform.cpp" "$UP/platform/io.cpp" "$UP/platform/linux/io_select_linux.cpp" "$HERE/machine.cpp" "$HERE/run-native.cpp"; do
  n=$((n+1))
  "$CXX" -std=gnu++11 -O2 -DUSE_BENCHMARK -D_POSIX \
    -I"$UP" -I"$UP/3rdparty/minizip" -I"$UP/3rdparty/tinyxml2" \
    -c "$f" -o "$OBJ/cxx_$n.o"
done
echo "build-native: compiling C..."
set -- -I"$UP"
if [ -n "$ZLIB_SRCS" ]; then
  set -- "$@" -I"$UP/3rdparty/zlib"
fi
for f in "$UP/3rdparty/minizip/ioapi.c" "$UP/3rdparty/minizip/unzip.c"; do
  n=$((n+1))
  "$CC" -O2 -D_POSIX "$@" -c "$f" -o "$OBJ/c_$n.o"
done
if [ -n "$ZLIB_SRCS" ]; then
  for f in "$ZLIB_SRCS"/*.c; do
    n=$((n+1))
    "$CC" -O2 -D_POSIX "$@" -c "$f" -o "$OBJ/c_$n.o"
  done
fi
echo "build-native: linking..."
"$CXX" "$OBJ"/*.o -o "$OUT/run-native" ${LDFLAGS:-}
echo "build-native: $OUT/run-native"
if command -v ldd >/dev/null 2>&1; then
  if ldd "$OUT/run-native" 2>/dev/null | grep -i -E 'SDL|libGL|openal|wx' ; then
    echo "build-native: FAILED — window-system linkage leaked in (see above)" >&2
    exit 1
  fi
fi
"$OUT/run-native" --help
