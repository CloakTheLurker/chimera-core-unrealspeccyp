#!/bin/sh
# Guest legs for the gate: build run-wbx (host driver) and run it.
# Usage: guest-legs.sh <frames> [extra run-wbx args...]
# Runs directly on Linux (a runner) and inside WSL from a Windows checkout.
# All tokens must be space-free (the WSL trampoline joins them into one arg
# string). A relative --settings-json name resolves under the guest build dir
# and is copied to GATE_SCRATCH: a space-free path that survives `wsl -t`
# (the gate kills WSL between the two-process legs).
# Prints run-wbx summary lines to stdout for the gate to parse.
# --expect-refuse: the file mounted with --game must be refused by the core, with
# a reason; prints "run-wbx refused: <reason>" and exits 0.
set -eu
. "$(dirname "$0")/env.sh"
FRAMES=${1:-600}
shift || true
GUEST_DIR="$WIN_CORE/build/guest"
SCRATCH=${GATE_SCRATCH:-/var/tmp/chimera-usp-gate}
mkdir -p "$SCRATCH"
ARGS=""
EXPECT_REFUSE=0
while [ $# -gt 0 ]; do
  if [ "$1" = "--settings-json" ]; then
    shift
    case "$1" in
      */*) SJ="$1";;
      *) cp "$GUEST_DIR/$1" "$SCRATCH/wbx-settings.json"; SJ="$SCRATCH/wbx-settings.json";;
    esac
    ARGS="$ARGS --settings-json $SJ"
    shift || true
  elif [ "$1" = "--game" ]; then
    shift
    # A bare basename resolves under the guest build dir (the gate stages
    # test-content there and passes a space-free basename, since the WSL
    # trampoline cannot carry spaced paths). An absolute/relative path with
    # a slash is used as-is. Either way the bytes land space-free in
    # GATE_SCRATCH, keeping the extension the guest loader dispatches on.
    case "$1" in */*) SRC="$1";; *) SRC="$GUEST_DIR/$1";; esac
    GB="$SCRATCH/$(basename "$SRC")"
    if [ "$SRC" != "$GB" ]; then cp "$SRC" "$GB"; fi
    ARGS="$ARGS --game $GB"
    shift || true
  elif [ "$1" = "--type-file" ]; then
    shift
    # Same space-free staging as --game (the typed string rides a file so
    # quotes and spaces survive the WSL trampoline verbatim).
    case "$1" in */*) TS="$1";; *) TS="$GUEST_DIR/$1";; esac
    TB="$SCRATCH/$(basename "$TS")"
    if [ "$TS" != "$TB" ]; then cp "$TS" "$TB"; fi
    ARGS="$ARGS --type-file $TB"
    shift || true
  elif [ "$1" = "--expect-refuse" ]; then
    # The engine's Init rule, from the core's side: a mounted file it cannot
    # open must be answered 0 with a reason, not booted empty. Prints the
    # reason on a line that starts with "run-wbx " so the gate's WSL leg can
    # find it with the same marker as a normal run.
    EXPECT_REFUSE=1
    shift || true
  else
    ARGS="$ARGS $1"
    shift || true
  fi
done
MB_HOST_INC="$MB_SRC/source/host"
MB_HOST_LIB="$MB_BUILD/source/host"
if [ ! -f "$MB_HOST_LIB/libminiboxhost.a" ]; then
  # A fresh Linux checkout has minibox configured by the guest link but its
  # host library is not one of the targets that link asked for. Build it.
  echo "guest-legs: miniBox host library missing; building it" >&2
  [ -f "$MB_BUILD/build.ninja" ] || $MESON setup "$MB_BUILD" "$MB_SRC" -Dguest_cpp=true >&2
  $NINJA -C "$MB_BUILD" source/host/libminiboxhost.a >&2
fi
gcc -O2 -I"$MB_HOST_INC" -I"$WIN_CORE/waterbox" \
  "$WIN_CORE/waterbox/run-wbx.c" -o "$GUEST_DIR/run-wbx" \
  -L"$MB_HOST_LIB" -lminiboxhost "-Wl,-rpath,$MB_HOST_LIB"
if [ "$EXPECT_REFUSE" = "1" ]; then
  set +e
  # shellcheck disable=SC2086
  REFUSED_OUT=$("$GUEST_DIR/run-wbx" --frames "$FRAMES" $ARGS "$GUEST_DIR/core.wbx" 2>&1)
  REFUSED_STATUS=$?
  set -e
  if [ "$REFUSED_STATUS" -eq 0 ]; then
    echo "guest-legs: the core accepted a file it must refuse (status 0)" >&2
    exit 1
  fi
  REFUSED_REASON=$(printf '%s\n' "$REFUSED_OUT" \
    | sed -n 's/^run-wbx: the core refused the file: //p' | head -n 1)
  if [ -z "$REFUSED_REASON" ]; then
    echo "guest-legs: no refusal reason; run-wbx said: $REFUSED_OUT" >&2
    exit 1
  fi
  echo "run-wbx refused: $REFUSED_REASON"
  exit 0
fi
# shellcheck disable=SC2086
"$GUEST_DIR/run-wbx" --frames "$FRAMES" $ARGS "$GUEST_DIR/core.wbx"
