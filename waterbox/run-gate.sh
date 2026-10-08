#!/bin/sh
# run-gate.sh — one command, and every leg says what it compared.
#
# Legs (gates.md: a leg never seen to fail is a leg not tested):
#  m0-build ......... native reference builds headless, no window linkage
#  m0-smoke ......... run-native boots firmware, steps 600 frames
#  m1-repeat ........ cross-process determinism: two runs, same state hash
#  m1-stall-300ms ... stall the host 300 ms mid-run; machine must not notice
#  m1-host-clock .... negative control: same stall under --clock host (the
#                     SDL platform's wall coupling: pad + drop late frames)
#                     MUST perturb the run (drops > 0, state differs). If it
#                     does not, this leg fails — the stall leg has no teeth.
#  m2-build ......... guest core.wbx links through the musl toolchain
#  m2-sandbox-clean  core.wbx passes miniBox check-wbx.sh (no TLS symbols,
#                     no %fs accesses, nothing below rsp)
#  m2-parity ........ native 600f vs guest 600f: tstates, vhash, bhash,
#                     mhash and state all equal — the sandbox did not change
#                     the answer. Guest legs run on Linux (natively on CI,
#                     inside WSL Ubuntu from a Windows checkout).
# Name the test content: exact file first (USP_TEST_CONTENT or test-content/
# glob), firmware boot (in-tree res/rom) when none. The content in use is
# always printed.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
NATIVE="$ROOT/build/native/run-native"
GUEST_WBX="$ROOT/build/guest/core.wbx"
CONTENT=${USP_TEST_CONTENT:-}
if [ -z "$CONTENT" ]; then
  CONTENT=$(ls "$ROOT"/test-content/* 2>/dev/null | head -n 1 || true)
fi
if [ -n "$CONTENT" ]; then
  echo "gate: content: $CONTENT"
  RUN_CONTENT="$CONTENT"
else
  echo "gate: content: (none — firmware boot: in-tree res/rom + step, no distributable content needed)"
  RUN_CONTENT=""
fi

# Run a tools/wsl/ leg on the guest-capable host: directly on Linux, via WSL
# (launch-and-poll through wsl-call.sh — see build-guest.sh for why).
on_guest_host() {
  if [ "$(uname -s)" = "Linux" ]; then
    mkdir -p "$ROOT/build/guest"
    sh "$ROOT/tools/wsl/$1" "$2" 2>&1 | tee "$ROOT/build/guest/${1%.sh}.log"
  else
    if ! command -v wsl.exe >/dev/null 2>&1; then
      echo "gate: guest legs need Linux (or WSL with Ubuntu); neither found" >&2
      exit 1
    fi
    export MSYS_NO_PATHCONV=1
    WSLROOT=$(cd "$ROOT" && pwd -W | tr "\134" "/" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
    . "$HERE/wsl-call.sh"
    case "$1" in
      check-wbx.sh) wsl_call "$1" "$2" "clean (no TLS" "$ROOT/build/guest/check-wbx.log" 300;;
      guest-legs.sh) wsl_call "$1" "$2" "^run-wbx " "$ROOT/build/guest/guest-legs.log" 600;;
      *) echo "gate: no marker for WSL leg $1" >&2; exit 1;;
    esac
  fi
}
state_of() {
  # state_of <run-native args...>: prints the state= hex of the summary line
  "$NATIVE" "$@" $RUN_CONTENT | tee /tmp/gate_last.log | sed -n 's/^run-native .* state=\([0-9a-f]*\) .*$/\1/p'
}
summary_of() { sed -n 's/^run-native \(.*\)$/\1/p' /tmp/gate_last.log; }
# field_of <file> <prefix> <field>: value of field= on the prefix's summary line
field_of() { sed -n "s/^$2 .* $3=\([^ ]*\) .*$/\1/p" "$1" | head -n 1; }

echo "gate leg m0-build: build-native.sh (headless, no SDL/GL linkage)"
"$HERE/build-native.sh" >/tmp/gate_build.log 2>&1
tail -n 1 /tmp/gate_build.log

echo "gate leg m0-smoke: run-native boots firmware, steps 600 frames, pulls audio+video"
S0=$(state_of --frames 600 --clock virtual)
echo "gate leg m0-smoke: $(summary_of)"

echo "gate leg m1-repeat: two virtual runs must agree (cross-process)"
S1=$(state_of --frames 600 --clock virtual)
echo "gate leg m1-repeat: run1=$S0 run2=$S1"
if [ "$S0" != "$S1" ]; then echo "gate leg m1-repeat: FAILED — same binary, same frames, different machine" >&2; exit 1; fi

echo "gate leg m1-stall-300ms: host sleeps 300 ms at frame 300, state must match $S0"
SS=$(state_of --frames 600 --clock virtual --stall-ms 300 --stall-at 300)
echo "gate leg m1-stall-300ms: stalled=$SS"
if [ "$SS" != "$S0" ]; then echo "gate leg m1-stall-300ms: FAILED — a host stall moved the machine" >&2; exit 1; fi

echo "gate leg m1-host-clock: negative control — wall-coupled run must NOTICE the stall"
HB=$(state_of --frames 200 --clock host)
echo "gate leg m1-host-clock: host-baseline: $(summary_of)"
HS=$(state_of --frames 200 --clock host --stall-ms 300 --stall-at 100)
echo "gate leg m1-host-clock: host-stalled:   $(summary_of)"
if [ "$HS" = "$HB" ]; then
  echo "gate leg m1-host-clock: FAILED — stall changed nothing under --clock host; the stall leg has no teeth" >&2
  exit 1
fi
DROPPED=$(sed -n 's/^run-native .* dropped=\([0-9]*\) .*$/\1/p' /tmp/gate_last.log)
if [ "${DROPPED:-0}" = "0" ]; then
  echo "gate leg m1-host-clock: FAILED — expected wall-coupled frame drops, saw none" >&2
  exit 1
fi
echo "gate leg m1-host-clock: teeth confirmed (stalled state $HS != baseline $HB, dropped=$DROPPED)"

if [ -z "${MINIBOX_DIR:-}" ]; then
  if [ -d "$HOME/chimera/extern/chimera-common-minibox" ]; then
    MINIBOX_DIR="$HOME/chimera/extern/chimera-common-minibox"
    export MINIBOX_DIR
  fi
fi
echo "gate leg m2-build: build-guest.sh into $GUEST_WBX (MINIBOX_DIR=${MINIBOX_DIR:-(unset)})"
MINIBOX_DIR="${MINIBOX_DIR:?m2 legs need MINIBOX_DIR (build-package.sh passes it down)}" \
  "$HERE/build-guest.sh" >/tmp/gate_guest_build.log 2>&1
tail -n 2 /tmp/gate_guest_build.log

echo "gate leg m2-sandbox-clean: miniBox check-wbx.sh on core.wbx"
if [ "$(uname -s)" = "Linux" ]; then
  sh "$MINIBOX_DIR/source/guest/check-wbx.sh" "$GUEST_WBX"
else
  on_guest_host check-wbx.sh unused
fi

echo "gate leg m2-parity: native 600f vs guest 600f must agree"
SN=$(state_of --frames 600 --clock virtual)
NT=$(field_of /tmp/gate_last.log run-native tstates)
NV=$(field_of /tmp/gate_last.log run-native vhash)
NB=$(field_of /tmp/gate_last.log run-native bhash)
NM=$(field_of /tmp/gate_last.log run-native mhash)
echo "gate leg m2-parity: native: $(summary_of)"
WBXLOG="$ROOT/build/guest/guest-legs.log"
on_guest_host guest-legs.sh 600
sed -n 's/^run-wbx \(.*\)$/guest: \1/p' "$WBXLOG" | tee /tmp/gate_wbx.log
SG=$(field_of /tmp/gate_wbx.log guest state)
GT=$(field_of /tmp/gate_wbx.log guest tstates)
GV=$(field_of /tmp/gate_wbx.log guest vhash)
GB=$(field_of /tmp/gate_wbx.log guest bhash)
GM=$(field_of /tmp/gate_wbx.log guest mhash)
echo "gate leg m2-parity: native=$SN guest=$SG"
mismatch=0
[ "$SN" = "$SG" ] || { echo "gate leg m2-parity: FAILED — state differs" >&2; mismatch=1; }
[ "$NT" = "$GT" ] || { echo "gate leg m2-parity: FAILED — tstates differ ($NT vs $GT)" >&2; mismatch=1; }
[ "$NV" = "$GV" ] || { echo "gate leg m2-parity: FAILED — vhash differs" >&2; mismatch=1; }
[ "$NB" = "$GB" ] || { echo "gate leg m2-parity: FAILED — bhash differs" >&2; mismatch=1; }
[ "$NM" = "$GM" ] || { echo "gate leg m2-parity: FAILED — mhash differs" >&2; mismatch=1; }
[ "$mismatch" = "0" ] || exit 1
echo "gate leg m2-parity: the sandbox did not change the answer"

echo "gate: done (all legs green)."
