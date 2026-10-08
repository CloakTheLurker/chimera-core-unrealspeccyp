#!/bin/sh
# run-gate.sh — one command, and every leg says what it compared.
#
# Legs (gates.md: a leg never seen to fail is a leg not tested):
#  m0-build ......... native reference builds headless, no window linkage
#  m0-smoke ......... run-native boots on in-tree firmware and steps 600 frames
#  m1-repeat ........ cross-process determinism: two runs, same state hash
#  m1-stall-300ms ... stall the host 300 ms mid-run; machine must not notice
#  m1-host-clock .... negative control: same stall under --clock host (the
#                     SDL platform's wall coupling: pad + drop late frames)
#                     MUST perturb the run (drops > 0, state differs). If it
#                     does not, this leg fails — the stall leg has no teeth.
# Name the test content: exact file first (USP_TEST_CONTENT or test-content/
# glob), firmware boot (in-tree res/rom) when none. The content in use is always printed.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
NATIVE="$ROOT/build/native/run-native"
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

state_of() {
  # state_of <run-native args...>: prints the state= hex of the summary line
  "$NATIVE" "$@" $RUN_CONTENT | tee /tmp/gate_last.log | sed -n 's/^run-native .* state=\([0-9a-f]*\) .*$/\1/p'
}
summary_of() { sed -n 's/^run-native \(.*\)$/\1/p' /tmp/gate_last.log; }

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

echo "gate: done (m2-sandbox-clean lands with the M2 guest build)."
