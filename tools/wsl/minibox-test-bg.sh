#!/bin/sh
# Detached miniBox build+test: survives the caller's timeout. Poll the log.
set -eu
. "$(dirname "$0")/env.sh"
LOG="$MB_BUILD/test-run.log"
nohup $MESON test -C "$MB_BUILD" > "$LOG" 2>&1 &
echo "started pid $! log $LOG"
