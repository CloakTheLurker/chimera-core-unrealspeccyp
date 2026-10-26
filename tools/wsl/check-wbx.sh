#!/bin/sh
# WSL leg of m2-sandbox-clean.
set -eu
. "$(dirname "$0")/env.sh"
sh "$MB_SRC/source/guest/check-wbx.sh" "$WIN_CORE/build/guest/core.wbx"
