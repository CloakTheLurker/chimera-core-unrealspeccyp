#!/bin/sh
# run-rom-matrix.sh — LOCAL-ONLY content matrix, never CI.
#
# The ROMs/ folder holds copyrighted files (untracked, gitignored); no CI
# runner has them, so this lives beside the gate instead of in it.
# Usage: run-rom-matrix.sh [--frames N] <game>...
# For each game file × all 8 sync-setting combos (mode48k × fastTape ×
# soundChip), native vs guest must agree on state+tstates+vhash+bhash+mhash
# — the settings channel is exercised end to end on real content.
# For tape content the mode48k combo must additionally MOVE the machine
# (ROM switch), or the matrix has no teeth.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/../.." && pwd -P)
NATIVE="$ROOT/build/native/run-native"
GUEST_WBX="$ROOT/build/guest/core.wbx"
GUEST_DIR="$ROOT/build/guest"
FRAMES=600
if [ "${1:-}" = "--frames" ]; then FRAMES="$2"; shift 2; fi
if [ $# -eq 0 ]; then echo "usage: $0 [--frames N] <game>..." >&2; exit 1; fi

# Same WSL trampoline as run-gate.sh (space-free tokens only).
if [ -z "${MINIBOX_DIR:-}" ]; then
  if [ -d "$ROOT/../chimera/extern/chimera-common-minibox" ]; then
    MINIBOX_DIR="$ROOT/../chimera/extern/chimera-common-minibox"
    export MINIBOX_DIR
  elif [ -d "$HOME/chimera/extern/chimera-common-minibox" ]; then
    MINIBOX_DIR="$HOME/chimera/extern/chimera-common-minibox"
    export MINIBOX_DIR
  fi
fi
on_guest_host() {
  if [ "$(uname -s)" = "Linux" ]; then
    mkdir -p "$GUEST_DIR"
    _script="$1"; shift
    sh "$ROOT/tools/wsl/$_script" "$@" 2>&1 | tee "$GUEST_DIR/${_script%.sh}.log"
  else
    if ! command -v wsl.exe >/dev/null 2>&1; then
      echo "matrix: guest legs need Linux (or WSL with Ubuntu); neither found" >&2
      exit 1
    fi
    export MSYS_NO_PATHCONV=1
    WSLROOT=$(cd "$ROOT" && pwd -W | tr "\134" "/" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
    . "$HERE/../wsl-call.sh"
    _script="$1"; shift
    wsl_call "$_script" "$*" "^run-wbx " "$GUEST_DIR/guest-legs.log" 900
  fi
}
state_of() {
  "$NATIVE" "$@" "$RUN_CONTENT" | tee /tmp/matrix_last.log | sed -n 's/^run-native .* state=\([0-9a-f]*\) .*$/\1/p'
}
summary_of() { sed -n 's/^run-native \(.*\)$/\1/p' /tmp/matrix_last.log; }
field_of() { sed -n "s/^$2 .* $3=\([^ ]*\) .*$/\1/p" "$1" | head -n 1; }

# The 8 sync-setting combos: native flags | settings JSON (guest reads the
# same keys through the mounted settings file; c0 states the defaults
# explicitly so every combo flows through the JSON channel).
mkdir -p "$GUEST_DIR"
printf '{}' > "$GUEST_DIR/m-c0.json"
printf '{"mode48k": true}' > "$GUEST_DIR/m-c1.json"
printf '{"fastTape": false}' > "$GUEST_DIR/m-c2.json"
printf '{"soundChip": "ym"}' > "$GUEST_DIR/m-c3.json"
printf '{"mode48k": true, "fastTape": false}' > "$GUEST_DIR/m-c4.json"
printf '{"mode48k": true, "soundChip": "ym"}' > "$GUEST_DIR/m-c5.json"
printf '{"fastTape": false, "soundChip": "ym"}' > "$GUEST_DIR/m-c6.json"
printf '{"mode48k": true, "fastTape": false, "soundChip": "ym"}' > "$GUEST_DIR/m-c7.json"

# $1 = combo id (c0..c7); prints native flags for run-native.
native_flags() {
  case "$1" in
    c0) ;;
    c1) printf '%s' '--mode48k';;
    c2) printf '%s' '--no-fast-tape';;
    c3) printf '%s' '--sound-chip ym';;
    c4) printf '%s' '--mode48k --no-fast-tape';;
    c5) printf '%s' '--mode48k --sound-chip ym';;
    c6) printf '%s' '--no-fast-tape --sound-chip ym';;
    c7) printf '%s' '--mode48k --no-fast-tape --sound-chip ym';;
  esac
}

WBXLOG="$GUEST_DIR/guest-legs.log"
for game in "$@"; do
  [ -f "$game" ] || { echo "matrix: no such file: $game" >&2; exit 1; }
  # Space-free stage name (the WSL trampoline cannot carry spaced paths);
  # the extension is kept — the guest loader dispatches on it.
  base=$(basename "$game")
  ext=${base##*.}
  stem=$(printf '%s' "${base%.*}" | tr -c 'A-Za-z0-9' '_' | tr -s '_')
  sbase="${stem}.${ext}"
  cp "$game" "$GUEST_DIR/$sbase"
  RUN_CONTENT="$game"
  echo "matrix: content: $game (as $sbase)"
  echo "matrix: native states per combo:"
  c0state=""
  c1state=""
  for c in c0 c1 c2 c3 c4 c5 c6 c7; do
    # shellcheck disable=SC2086
    SN=$(state_of --frames "$FRAMES" --clock virtual $(native_flags "$c"))
    NT=$(field_of /tmp/matrix_last.log run-native tstates)
    NV=$(field_of /tmp/matrix_last.log run-native vhash)
    NB=$(field_of /tmp/matrix_last.log run-native bhash)
    NM=$(field_of /tmp/matrix_last.log run-native mhash)
    echo "matrix:   native $c: state=$SN"
    if [ "$c" = "c0" ]; then c0state="$SN"; fi
    if [ "$c" = "c1" ]; then c1state="$SN"; fi
    on_guest_host guest-legs.sh "$FRAMES" --game "$sbase" --settings-json "m-$c.json"
    sed -n 's/^run-wbx /guest /p' "$WBXLOG" | tee /tmp/matrix_wbx.log
    SG=$(field_of /tmp/matrix_wbx.log guest state)
    mismatch=0
    [ "$SN" = "$SG" ] || { echo "matrix: FAILED ($base $c) — state differs (native=$SN guest=$SG)" >&2; mismatch=1; }
    [ "$NT" = "$(field_of /tmp/matrix_wbx.log guest tstates)" ] || { echo "matrix: FAILED ($base $c) — tstates differ" >&2; mismatch=1; }
    [ "$NV" = "$(field_of /tmp/matrix_wbx.log guest vhash)" ] || { echo "matrix: FAILED ($base $c) — vhash differs" >&2; mismatch=1; }
    [ "$NB" = "$(field_of /tmp/matrix_wbx.log guest bhash)" ] || { echo "matrix: FAILED ($base $c) — bhash differs" >&2; mismatch=1; }
    [ "$NM" = "$(field_of /tmp/matrix_wbx.log guest mhash)" ] || { echo "matrix: FAILED ($base $c) — mhash differs" >&2; mismatch=1; }
    [ "$mismatch" = "0" ] || exit 1
    echo "matrix:   $base $c: native==guest ($SN)"
  done
  case "$ext" in
    [Tt][Aa][Pp]|[Tt][Zz][Xx]|[Cc][Ss][Ww])
      # Tape boots through the ROM: the mode48k ROM switch must move it.
      [ "$c1state" != "$c0state" ] || { echo "matrix: FAILED ($base) — mode48k changed nothing on tape content; the matrix has no teeth" >&2; exit 1; }
      echo "matrix: teeth confirmed (mode48k moves $base: $c0state -> $c1state)";;
    *) echo "matrix: note: $base is a snapshot (devices come from the image); parity across all 8 combos is the assertion";;
  esac
done
echo "matrix: done (all combos green)."
