#!/bin/sh
# Copy the minibox source (submodule) to a space-free WSL-native dir.
# WHY: musl's configure (and the libstdc++ configure behind it) cannot handle
# spaces in srcdir/builddir ("Chimera Dev" breaks them). gcc itself is fine
# with quoted -I paths, so only the miniBox *source+build* moves native; the
# core sources stay in-tree. Re-run after any submodule bump of minibox.
# Usage: mb-sync.sh
set -eu
. "$(dirname "$0")/env.sh"
mkdir -p "$MB_NATIVE"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude=.git --exclude=build/ "$MINIBOX/" "$MB_SRC/"
else
  rm -rf "$MB_SRC"
  mkdir -p "$MB_SRC"
  cp -a "$MINIBOX/." "$MB_SRC/"
  rm -rf "$MB_SRC/build" "$MB_SRC/.git"
fi
echo "mb-sync: $MINIBOX -> $MB_SRC"
diff -r --brief "$MINIBOX/extern/musl/arch/waterbox" "$MB_SRC/extern/musl/arch/waterbox" && echo "mb-sync: waterbox glue matches"
