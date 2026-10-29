#!/bin/sh
# Detached guest link: survives the caller's timeout. Poll build/guest/link.log.
set -eu
. "$(dirname "$0")/env.sh"
# WSL now ships system meson/ninja (docs/BUILDING.md); MESON/NINJA from env.sh.
LOG="$WIN_CORE/build/guest/link.log"
nohup sh "$WIN_CORE/waterbox/guest-link.sh" "$WIN_CORE" "$MINIBOX" "$WIN_CORE/build/guest" > "$LOG" 2>&1 &
echo "started pid $! log $LOG"
