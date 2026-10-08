#!/bin/sh
# Detached guest link: survives the caller's timeout. Poll build/guest/link.log.
set -eu
. "$(dirname "$0")/env.sh"
export MESON="python3 $HOME/tools/meson-1.7.0/meson.py"
export NINJA="$HOME/.local/bin/ninja"
LOG="$WIN_CORE/build/guest/link.log"
nohup sh "$WIN_CORE/waterbox/guest-link.sh" "$WIN_CORE" "$MINIBOX" "$WIN_CORE/build/guest" > "$LOG" 2>&1 &
echo "started pid $! log $LOG"
