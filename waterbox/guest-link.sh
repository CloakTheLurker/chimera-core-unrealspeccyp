#!/bin/sh
# guest-link.sh — link core.wbx on LINUX (runs under WSL here, natively on CI).
#
# Usage: guest-link.sh <core-root> <minibox-dir> <out-dir>   (all Linux paths)
#
# Uses the miniBox guest toolchain (musl-gcc + emulibc + guest libstdc++),
# the FROZEN flag sets from minibox source/guest/meson.build, and the C++
# link recipe from tests/cpp/meson.build (order is load-bearing). No absolute
# paths are baked in: MINIBOX_DIR arrives from build-package.sh, everything
# else derives from it.
set -eu
CORE="$1"; MINIBOX="$2"; OUT="$3"
U="$CORE/extern/upstream"
MB_BUILD="$MINIBOX/build/meson-linux"
SYSROOT="$MB_BUILD/guest-sysroot"
MUSL_GCC="$MB_BUILD/musl-gcc"
EMULIBC_OBJ="$MB_BUILD/source/guest/emulibc.c.o"
CXXGLUE_OBJ="$MB_BUILD/source/guest/cxxglue.c.o"
LINKSCRIPT="$MINIBOX/source/guest/linkscript.T"
# Toolchain bootstrap: miniBox builds musl + the guest C++ stdlib itself, but
# meson marks those custom targets build_by_default=false — plain `ninja`
# skips them (only `meson test` would pull them via test deps). So ask for
# them by name; resumable, one-time cost (~84MB GCC fetch + ~75 CPU-s).
MESON_BIN="${MESON:-meson}"
NINJA_BIN="${NINJA:-ninja}"
if [ ! -f "$MB_BUILD/build.ninja" ]; then
  case "$MESON_BIN" in *" "*) ;; *) command -v "$MESON_BIN" >/dev/null 2>&1 || { echo "guest-link: need meson (or MESON=...) to configure miniBox" >&2; exit 1; };; esac
  # MESON may be "python3 path/meson.py": word-split intended.
  # shellcheck disable=SC2086
  $MESON_BIN setup "$MB_BUILD" "$MINIBOX" -Dguest_cpp=true
fi
# NINJA may be "path/ninja with args": word-split intended.
# shellcheck disable=SC2086
$NINJA_BIN -C "$MB_BUILD" musl-gcc source/guest/emulibc.c.o source/guest/cxxglue.c.o libstdcxx-installed.stamp
for f in "$MUSL_GCC" "$EMULIBC_OBJ" "$CXXGLUE_OBJ" "$LINKSCRIPT"; do
  if [ ! -f "$f" ]; then echo "guest-link: missing $f after toolchain build" >&2; exit 1; fi
done

command -v g++ readelf objdump >/dev/null || { echo "guest-link: need g++ readelf objdump on PATH" >&2; exit 1; }
if [ ! -f "$SYSROOT/lib/libstdc++.a" ]; then echo "guest-link: no guest libstdc++ — configure miniBox with -Dguest_cpp=true" >&2; exit 1; fi
GCC_VER=$(g++ -dumpfullversion)
GXX_INC="$SYSROOT/include/c++/$GCC_VER"
if [ ! -d "$GXX_INC" ]; then echo "guest-link: no $GXX_INC (host g++ $GCC_VER != toolchain compiler?)" >&2; exit 1; fi

# Frozen guest flags (minibox source/guest/meson.build: waterbox_guest_cflags).
GCFLAGS="-fvisibility=hidden -I$MINIBOX/extern/emulibc -I$MINIBOX/source/guest/include -I$MINIBOX/extern/jsmn -Wall -mcmodel=large -mno-red-zone -mstack-protector-guard=global -fno-stack-protector -fno-pic -fno-pie -fcf-protection=none -O2 -DNDEBUG"
# No thread-local storage: a TLS write with no thread pointer lands wherever
# %fs happens to point. check-wbx.sh enforces this on the linked image.
GCFLAGS="$GCFLAGS -Dthread_local= -D_Thread_local= -D__thread="
SPECS="$SYSROOT/lib/musl-gcc.specs"
GCXXFLAGS="$GCFLAGS -specs $SPECS -I$GXX_INC -I$GXX_INC/x86_64-linux-musl -fno-exceptions -fno-rtti"
# load-bearing link order: -lstdc++ -lgcc -lgcc_eh -lc, libc LAST; --no-relax
# for large-model GOTPCREL; -u pthread_* to force weak libgcc_eh refs.
GLDFLAGS="-static -no-pie -Wl,--eh-frame-hdr,-O2,--no-relax -T $LINKSCRIPT -Wl,-u,pthread_once -Wl,-u,pthread_cond_wait -Wl,-u,pthread_cond_broadcast -Wl,-u,pthread_key_create"
GLIBS="-L$SYSROOT/lib -lstdc++ -lgcc -lgcc_eh -lc"

# Same TU list as build-native.sh, plus the guest entry. C++ via g++, C via
# musl-gcc (zlib is not C++-clean). -DWBX_GUEST enables the guest-only hooks.
mkdir -p "$OUT/obj"
rm -f "$OUT/obj/"*.o
n=0
for d in "" z80 tools snapshot devices devices/fdd devices/input devices/sound; do
  for f in "$U/$d/"*.cpp; do
    [ -f "$f" ] || continue
    n=$((n+1))
    # shellcheck disable=SC2086
    g++ -std=c++17 -DWBX_GUEST -D_POSIX $GCXXFLAGS -I"$U" -I"$U/3rdparty/minizip" -I"$U/3rdparty/tinyxml2" -I"$CORE/waterbox" -c "$f" -o "$OUT/obj/g$n.o"
  done
done
for f in "$U/3rdparty/tinyxml2/tinyxml2.cpp" "$U/platform/platform.cpp" "$U/platform/io.cpp" "$U/platform/linux/io_select_linux.cpp" "$CORE/waterbox/machine.cpp" "$CORE/waterbox/wbx-entry.cpp" "$CORE/waterbox/guest-syscalls.cpp"; do
  n=$((n+1))
  # shellcheck disable=SC2086
  g++ -std=c++17 -DWBX_GUEST -D_POSIX $GCXXFLAGS -I"$U" -I"$U/3rdparty/minizip" -I"$U/3rdparty/tinyxml2" -I"$CORE/waterbox" -c "$f" -o "$OUT/obj/g$n.o"
done
for f in "$U/3rdparty/minizip/ioapi.c" "$U/3rdparty/minizip/unzip.c" "$U"/3rdparty/zlib/*.c; do
  n=$((n+1))
  # shellcheck disable=SC2086
  "$MUSL_GCC" -std=c11 -DWBX_GUEST -D_POSIX $GCFLAGS -I"$U" -I"$U/3rdparty/zlib" -c "$f" -o "$OUT/obj/g$n.o"
done
echo "guest-link: $n objects; linking core.wbx..."
# shellcheck disable=SC2086
g++ $GLDFLAGS -o "$OUT/core.wbx" "$OUT/obj/"g*.o "$CXXGLUE_OBJ" "$EMULIBC_OBJ" $GLIBS
echo "guest-link: hygiene (TLS/%fs/red-zone)..."
sh "$MINIBOX/source/guest/check-wbx.sh" "$OUT/core.wbx"
ls -la "$OUT/core.wbx"
