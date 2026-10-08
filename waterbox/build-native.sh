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
# Numbering is positional over a fixed TU order, so objects are resumable:
# an .o newer than its source is kept. (A flag change needs rm obj/ by hand.)
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
U="$ROOT/extern/upstream"
OUT="$ROOT/build/native"
UP="$ROOT/build/upstream-patched"
OBJ="$OUT/obj"
mkdir -p "$OUT" "$OBJ"

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
set -- -I"$UP" -I"$UP/3rdparty/minizip" -I"$UP/3rdparty/tinyxml2"
if [ -n "$ZLIB_SRCS" ]; then
  set -- "$@" -I"$UP/3rdparty/zlib"
fi

I1="-I$UP"; I2="-I$UP/3rdparty/minizip"; I3="-I$UP/3rdparty/tinyxml2"; I4=""
if [ -n "$ZLIB_SRCS" ]; then
  I4="-I$UP/3rdparty/zlib"
fi

echo "build-native: compiling (M0 headless reference)..."
n=0
compile_cxx() {
  n=$((n+1))
  if [ -f "$OBJ/cxx_$n.o" ] && [ "$OBJ/cxx_$n.o" -nt "$1" ]; then return 0; fi
  # Atomic landing (.tmp + mv): a KILLed compiler must never leave a
  # partial .o newer than its source, or the resume check would bless it.
  "$CXX" -std=gnu++11 -O2 -DUSE_BENCHMARK -D_POSIX "$I1" "$I2" "$I3" ${I4:+"$I4"} -c "$1" -o "$OBJ/cxx_$n.o.tmp" && mv "$OBJ/cxx_$n.o.tmp" "$OBJ/cxx_$n.o"
}
compile_c() {
  n=$((n+1))
  if [ -f "$OBJ/c_$n.o" ] && [ "$OBJ/c_$n.o" -nt "$1" ]; then return 0; fi
  "$CC" -O2 -D_POSIX "$I1" ${I4:+"$I4"} -c "$1" -o "$OBJ/c_$n.o.tmp" && mv "$OBJ/c_$n.o.tmp" "$OBJ/c_$n.o"
}
for d in "" z80 tools snapshot devices devices/fdd devices/input devices/sound; do
  for f in "$UP/$d/"*.cpp; do
    [ -f "$f" ] || continue
    compile_cxx "$f"
  done
done
for f in "$UP/3rdparty/tinyxml2/tinyxml2.cpp" "$UP/platform/platform.cpp" "$UP/platform/io.cpp" "$UP/platform/linux/io_select_linux.cpp" "$HERE/machine.cpp" "$HERE/run-native.cpp"; do
  compile_cxx "$f"
done
for f in "$UP/3rdparty/minizip/ioapi.c" "$UP/3rdparty/minizip/unzip.c"; do
  compile_c "$f"
done
if [ -n "$ZLIB_SRCS" ]; then
  for f in "$ZLIB_SRCS"/*.c; do
    compile_c "$f"
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
