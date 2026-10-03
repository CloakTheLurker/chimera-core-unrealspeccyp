#!/bin/sh
# build-native.sh — M0: headless native build, no frontend, no window system.
#
# Compiles upstream core sources (root *.cpp, z80/, tools/, snapshot/,
# devices/..., 3rdparty/minizip, 3rdparty/tinyxml2, vendored 3rdparty/zlib)
# plus platform/platform.cpp, platform/io.cpp, a POSIX io_select, and the
# waterbox/ adapter + run-native.cpp harness — with USE_BENCHMARK semantics:
# no USE_SDL / USE_SDL2 / USE_WXWIDGETS / USE_GL / USE_OAL / USE_UI /
# USE_CURL / USE_WEB. No SDL/GL/window linkage allowed in the output.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
U="$ROOT/extern/upstream"
OUT="$ROOT/build/native"
mkdir -p "$OUT"

"$HERE/apply-patches.sh"

CXX=${CXX:-g++}
# M0 source list mirrors usp build/cmake core globs minus every UI/platform.
# (Kept as a shell glob list, not cmake, so the headless constraint is visible.)
SRCS=""
for d in "" z80 tools snapshot devices devices/fdd devices/input devices/sound; do
  for f in "$U/$d"/*.cpp; do
    [ -f "$f" ] && SRCS="$SRCS $f"
  done
done
SRCS="$SRCS $U/3rdparty/minizip/ioapi.c $U/3rdparty/minizip/unzip.c"
SRCS="$SRCS $U/3rdparty/tinyxml2/tinyxml2.cpp"
SRCS="$SRCS $U/platform/platform.cpp $U/platform/io.cpp"
SRCS="$SRCS $HERE/machine.cpp $HERE/run-native.cpp"

echo "build-native: compiling M0 headless reference..."
# shellcheck disable=SC2086
$CXX -std=gnu++11 -O2 -DUSE_BENCHMARK -D_POSIX \
  -I"$U" -I"$U/3rdparty/minizip" -I"$U/3rdparty/tinyxml2" \
  $SRCS -o "$OUT/run-native" ${LDFLAGS:-}
echo "build-native: $OUT/run-native"
if command -v ldd >/dev/null 2>&1; then
  if ldd "$OUT/run-native" 2>/dev/null | grep -i -E 'SDL|libGL|openal|wx' ; then
    echo "build-native: FAILED — window-system linkage leaked in (see above)" >&2
    exit 1
  fi
fi
"$OUT/run-native" --help
