#!/bin/sh
# WSL leg of m2-sandbox-clean.
set -eu
. "$(dirname "$0")/env.sh"
sh "$MINIBOX/source/guest/check-wbx.sh" "$WIN_CORE/build/guest/core.wbx"
