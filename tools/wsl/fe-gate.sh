#!/bin/sh
# WSL leg for the gate's frontend suite: runs tests/run-frontend.sh, which
# prints "fe: ..." lines and ends with "fe: done (all legs green)."
# All repo paths are space-free inside WSL (quoted); the gate polls the log
# for the done marker through wsl-call.sh, like the other WSL legs.
set -eu
. "$(dirname "$0")/env.sh"
sh "$WIN_CORE/waterbox/tests/run-frontend.sh"
