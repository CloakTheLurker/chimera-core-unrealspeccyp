#!/bin/sh
# WSL legs for the gate: build run-wbx (host driver) and run it.
# Usage: guest-legs.sh <frames> [extra run-wbx args...]
# All tokens must be space-free (the gate joins them into one WSL arg string).
# A relative --settings-json name resolves under the guest build dir; it is
# copied to /home/cloak (space-free, survives wsl -t) because the resolved
# repo path has spaces and would word-split.
# Prints run-wbx summary lines to stdout for the gate to parse.
set -eu
. "$(dirname "$0")/env.sh"
FRAMES=${1:-600}
shift || true
GUEST_DIR="$WIN_CORE/build/guest"
ARGS=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--settings-json" ]; then
    shift
    case "$1" in
      */*) SJ="$1";;
      *) cp "$GUEST_DIR/$1" /home/cloak/wbx-settings.json; SJ="/home/cloak/wbx-settings.json";;
    esac
    ARGS="$ARGS --settings-json $SJ"
    shift || true
  else
    ARGS="$ARGS $1"
    shift || true
  fi
done
MB_HOST_INC="$MB_SRC/source/host"
MB_HOST_LIB="$MB_BUILD/source/host"
gcc -O2 -I"$MB_HOST_INC" -I"$WIN_CORE/waterbox" \
  "$WIN_CORE/waterbox/run-wbx.c" -o "$GUEST_DIR/run-wbx" \
  -L"$MB_HOST_LIB" -lminiboxhost "-Wl,-rpath,$MB_HOST_LIB"
# shellcheck disable=SC2086
"$GUEST_DIR/run-wbx" --frames "$FRAMES" $ARGS "$GUEST_DIR/core.wbx"
