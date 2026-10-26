#!/bin/sh
# WSL leg of build-guest.sh: native-space-free minibox paths via env.sh.
set -eu
. "$(dirname "$0")/env.sh"
export MB_SRC_DIR="$MB_SRC" MB_BUILD_DIR="$MB_BUILD"
sh "$WIN_CORE/waterbox/guest-link.sh" "$WIN_CORE" "$MINIBOX" "$WIN_CORE/build/guest"
