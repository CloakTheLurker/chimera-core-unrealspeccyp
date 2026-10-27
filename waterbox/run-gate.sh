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
#  m3-input-teeth ... Space+Enter held 600f MUST perturb the firmware run
#                     (input reaches the machine). If it does not, this leg
#                     fails — the input legs have no teeth.
#  m3-input-parity .. guest with Space+Enter 600f agrees with native — input
#                     is levels applied identically in both flavors.
#  m3-rerecord ...... guest save+load around EVERY frame equals a plain run
#                     (anything of the machine outside the arena shows up).
#  m3-session ....... save at frame 299 in one process, continue 300 in
#                     another: tstates + last-frame video/audio equal the
#                     uninterrupted run (what a movie asks of a core).
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
# Extra args ($3...) are joined into the single WSL arg string (all M3 leg
# tokens are space-free flags/numbers) and re-split by sh inside WSL.
on_guest_host() {
  if [ "$(uname -s)" = "Linux" ]; then
    mkdir -p "$ROOT/build/guest"
    _script="$1"; shift
    sh "$ROOT/tools/wsl/$_script" "$@" 2>&1 | tee "$ROOT/build/guest/${_script%.sh}.log"
  else
    if ! command -v wsl.exe >/dev/null 2>&1; then
      echo "gate: guest legs need Linux (or WSL with Ubuntu); neither found" >&2
      exit 1
    fi
    export MSYS_NO_PATHCONV=1
    WSLROOT=$(cd "$ROOT" && pwd -W | tr "\134" "/" | sed 's|^\([A-Za-z]\):|/mnt/\L\1|')
    . "$HERE/wsl-call.sh"
    _script="$1"; shift
    case "$_script" in
      check-wbx.sh) wsl_call "$_script" "$*" "clean (no TLS" "$ROOT/build/guest/check-wbx.log" 300;;
      guest-legs.sh) wsl_call "$_script" "$*" "^run-wbx " "$ROOT/build/guest/guest-legs.log" 900;;
      *) echo "gate: no marker for WSL leg $_script" >&2; exit 1;;
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
  if [ -d "$ROOT/../chimera/extern/chimera-common-minibox" ]; then
    MINIBOX_DIR="$ROOT/../chimera/extern/chimera-common-minibox"
    export MINIBOX_DIR
  elif [ -d "$HOME/chimera/extern/chimera-common-minibox" ]; then
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
sed -n 's/^run-wbx /guest /p' "$WBXLOG" | tee /tmp/gate_wbx.log
SG=$(field_of /tmp/gate_wbx.log guest state)
GT=$(field_of /tmp/gate_wbx.log guest tstates)
GV=$(field_of /tmp/gate_wbx.log guest vhash)
GB=$(field_of /tmp/gate_wbx.log guest bhash)
GM=$(field_of /tmp/gate_wbx.log guest mhash)
GLV=$(field_of /tmp/gate_wbx.log guest lvhash)
GLM=$(field_of /tmp/gate_wbx.log guest lmhash)
echo "gate leg m2-parity: native=$SN guest=$SG"
mismatch=0
[ "$SN" = "$SG" ] || { echo "gate leg m2-parity: FAILED — state differs" >&2; mismatch=1; }
[ "$NT" = "$GT" ] || { echo "gate leg m2-parity: FAILED — tstates differ ($NT vs $GT)" >&2; mismatch=1; }
[ "$NV" = "$GV" ] || { echo "gate leg m2-parity: FAILED — vhash differs" >&2; mismatch=1; }
[ "$NB" = "$GB" ] || { echo "gate leg m2-parity: FAILED — bhash differs" >&2; mismatch=1; }
[ "$NM" = "$GM" ] || { echo "gate leg m2-parity: FAILED — mhash differs" >&2; mismatch=1; }
[ "$mismatch" = "0" ] || exit 1
echo "gate leg m2-parity: the sandbox did not change the answer"

echo "gate leg m3-input-teeth: Space+Enter held 600f must perturb the machine"
SNK=$(state_of --frames 600 --clock virtual --input-keys 0x3 --input-from 0 --input-to 600)
echo "gate leg m3-input-teeth: no-input=$S0 input=$SNK"
if [ "$SNK" = "$S0" ]; then echo "gate leg m3-input-teeth: FAILED — input changed nothing; the leg has no teeth" >&2; exit 1; fi

echo "gate leg m3-input-parity: guest with Space+Enter 600f must agree with native"
on_guest_host guest-legs.sh 600 --input-keys 0x3 --input-from 0 --input-to 600
sed -n 's/^run-wbx /guest /p' "$WBXLOG" | tee /tmp/gate_wbx.log
GK=$(field_of /tmp/gate_wbx.log guest state)
echo "gate leg m3-input-parity: native=$SNK guest=$GK"
[ "$SNK" = "$GK" ] || { echo "gate leg m3-input-parity: FAILED — input run differs across flavors" >&2; exit 1; }

echo "gate leg m3-rerecord: guest save+load around EVERY frame must equal a plain run"
on_guest_host guest-legs.sh 600 --rerecord
sed -n 's/^run-wbx /guest /p' "$WBXLOG" | tee /tmp/gate_wbx.log
GR=$(field_of /tmp/gate_wbx.log guest state)
echo "gate leg m3-rerecord: plain=$SG rerecord=$GR"
[ "$SG" = "$GR" ] || { echo "gate leg m3-rerecord: FAILED — machine state lives outside the arena snapshot" >&2; exit 1; }

if [ "$(uname -s)" != "Linux" ]; then
  # Fresh WSL session for the two-process dance: long gate runs degrade the
  # session (wedged starts fail fast with no marker), and a save split
  # across a wedged boundary proves nothing.
  export MSYS_NO_PATHCONV=1
  wsl.exe -t Ubuntu 2>/dev/null || true
  sleep 10
fi
echo "gate leg m3-session: save at frame 299 in one process, continue 300 in another"
on_guest_host guest-legs.sh 300 --save-at 299 --save-to /home/cloak/m3-session.state
on_guest_host guest-legs.sh 300 --continue-from /home/cloak/m3-session.state
sed -n 's/^run-wbx /guest /p' "$WBXLOG" | tee /tmp/gate_wbx.log
CT=$(field_of /tmp/gate_wbx.log guest tstates)
CLV=$(field_of /tmp/gate_wbx.log guest lvhash)
CLM=$(field_of /tmp/gate_wbx.log guest lmhash)
echo "gate leg m3-session: continued tstates=$CT lvhash=$CLV lmhash=$CLM"
[ "$GT" = "$CT" ] || { echo "gate leg m3-session: FAILED — tstates differ ($GT vs $CT)" >&2; exit 1; }
[ "$GLV" = "$CLV" ] || { echo "gate leg m3-session: FAILED — last-frame video differs" >&2; exit 1; }
[ "$GLM" = "$CLM" ] || { echo "gate leg m3-session: FAILED — last-frame audio differs" >&2; exit 1; }
echo "gate leg m3-session: a savestate taken mid-run resumes the same machine"
echo "gate leg m3-session: save file lives at /home/cloak/m3-session.state (native ext4: survives wsl -t, unlike /tmp)"

echo "gate leg m4-settings-teeth: mode48k must perturb the firmware boot (native)"
SN48=$(state_of --frames 600 --clock virtual --mode48k)
echo "gate leg m4-settings-teeth: default=$S0 mode48k=$SN48"
[ "$SN48" != "$S0" ] || { echo "gate leg m4-settings-teeth: FAILED — mode48k changed nothing; the leg has no teeth" >&2; exit 1; }

echo "gate leg m4-settings-parity: guest with mode48k+ym agrees with native"
printf '{"mode48k": true, "soundChip": "ym"}' > "$ROOT/build/guest/m48ym.json"
SN48YM=$(state_of --frames 600 --clock virtual --mode48k --sound-chip ym)
echo "gate leg m4-settings-parity: native: $(summary_of)"
on_guest_host guest-legs.sh 600 --settings-json m48ym.json
sed -n 's/^run-wbx /guest /p' "$WBXLOG" | tee /tmp/gate_wbx.log
SG48=$(field_of /tmp/gate_wbx.log guest state)
echo "gate leg m4-settings-parity: native=$SN48YM guest=$SG48"
[ "$SN48YM" = "$SG48" ] || { echo "gate leg m4-settings-parity: FAILED — settings run differs across flavors" >&2; exit 1; }
echo "gate leg m4-settings-parity: the settings channel reaches the machine identically in both flavors"

echo "gate: done (all legs green)."
