#!/bin/sh
# run-frontend.sh — the M5 frontend gate (Level B): the real Chimera frontend,
# headless under mono+Xvfb, boots the packaged core with distributable
# content, and every leg says what it compared.
#
# Runs on Linux: natively, or inside WSL Ubuntu (tools/wsl/fe-gate.sh wraps
# it for the gate's launch-and-poll trampoline). All paths are quoted (the
# tree lives under "Chimera Dev" — spaces are load-bearing).
#
# Legs (a leg never seen to fail is a leg not tested):
#  fe-boot ......... TAP boots through the real session pipeline: system id
#                    ZXS, 600 frames advance, screenshot lands, meta says OK.
#                    (Without content no core loads and getsystemid() is nil —
#                    the probe failed exactly that way, so this leg has teeth.)
#  fe-determinism .. the same boot twice gives byte-identical screenshots.
#  fe-input ........ Space+Enter held (bits 20,21 of the 64-bit button mask)
#                    gives a DIFFERENT screenshot — frontend input reaches the
#                    machine through joypad + the declared input mnemonics.
#  fe-rerecord ..... per-frame save+load around every frame equals the plain
#                    run (the frontend savestate path is sound).
#  fe-keybinds ..... all 62 declared buttons set at once (bits 0-21 by mask,
#                    the P5 keyboard by whole name past Lua's float range):
#                    the run completes (every name resolves through the real
#                    input pipeline) and differs from the plain run.
# Settings reach the machine through the same mount the driver uses; that
# channel is gated at driver level (m4/m5-content-settings-parity). Headless
# sessions run package defaults, so there is no headless settings knob left
# to turn here without inventing one.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/../.." && pwd -P)

. "$ROOT/tools/wsl/env.sh" 2>/dev/null || {
  # Native Linux checkout (no WSL): derive the same names from the repo root.
  WIN_DEV="$ROOT"
  WIN_CHIMERA="$ROOT/chimera"
  WIN_CORE="$ROOT/chimera-core-unrealspeccyp"
  MB_NATIVE="$HOME/mb"
  MB_SRC="$MB_NATIVE/minibox"
  MB_BUILD="$MB_NATIVE/build"
  MINIBOX="$WIN_CHIMERA/extern/chimera-common-minibox"
}

CORE="$WIN_CORE"
CHIMERA="$WIN_CHIMERA"
W="$CORE/waterbox/tests/work"
PKGDIR="$CORE/build/frontend-pkg"
TAP="$CORE/test-content/boot.tap"
FRAMES=600

[ -f "$TAP" ] || { echo "fe: FAILED — $TAP missing (test-content is the distributable content)" >&2; exit 1; }

echo "fe: package dir: $PKGDIR"
mkdir -p "$PKGDIR"
cp "$CORE/waterbox/waterbox.config" "$CORE/waterbox/file_slots.json" \
   "$CORE/waterbox/default_keybinds.json" "$PKGDIR/"
cp "$CORE/build/guest/core.wbx" "$PKGDIR/"
COMMIT=$(git -C "$CORE" rev-parse HEAD 2>/dev/null || echo unknown)
WHEN=$(git -C "$CORE" log -1 --format=%cI 2>/dev/null || echo unknown)
python3 - "$PKGDIR/waterbox.config" "$COMMIT" "$WHEN" <<'PY'
import json, sys
path, commit, when = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    cfg = json.load(f)
cfg["version"] = commit
cfg["versionDate"] = when
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(f"fe: stamped version={commit}")
PY

if [ ! -f "$W/config.ini" ]; then
  echo "fe: bootstrap config"
  mkdir -p "$W/data-home"
  export LD_LIBRARY_PATH="$CHIMERA/build/dll"
  export MONO_CRASH_NOFILE=1 MONO_WINFORMS_XIM_STYLE=disabled ALSOFT_DRIVERS=null
  export XDG_DATA_HOME="$W/data-home"
  if [ -z "${DISPLAY:-}" ]; then
    Xvfb :91 -screen 0 640x480x24 -nolisten tcp &
    export DISPLAY=:91
    sleep 1
  fi
  (cd "$CHIMERA" && timeout 120 mono build/Chimera.exe --headless "--config=$W/config.ini" "--lua=$CORE/waterbox/tests/work-bootstrap.lua")
  ls -la "$W/config.ini"
fi

export LD_LIBRARY_PATH="$CHIMERA/build/dll"
export MONO_CRASH_NOFILE=1 MONO_WINFORMS_XIM_STYLE=disabled ALSOFT_DRIVERS=null
export XDG_DATA_HOME="$W/data-home"
if [ -z "${DISPLAY:-}" ]; then
  for n in 91 92 93 94; do
    if [ ! -e "/tmp/.X11-unix/X$n" ]; then
      Xvfb ":$n" -screen 0 640x480x24 -nolisten tcp &
      export DISPLAY=":$n"; break
    fi
  done
  sleep 1
fi
U="$CORE/extern/upstream/res/rom"

# The P5 keyboard names, read from the packaged declaration (never drifts
# from waterbox.config): the keybinds leg holds every one every frame.
P5KEYS=$(python3 - "$PKGDIR/waterbox.config" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
print(",".join(b for b in cfg["input"]["buttons"] if b.startswith("P5 ")))
PY
)
case "$P5KEYS" in P5*) ;; *) echo "fe: FAILED — no P5 keys in $PKGDIR/waterbox.config" >&2; exit 1;; esac

fe_run() { # <tag> <frames> <mask> <extra> <rerecord 0|1> — game positional LAST
  _tag="$1"; _frames="$2"; _mask="$3"; _extra="$4"; _rr="$5"
  printf 'frames=%s\ninput=%s\nextra=%s\nrerecord=%s\nshot=%s/shot-%s.png\nmeta=%s/meta-%s.txt\n' \
    "$_frames" "$_mask" "$_extra" "$_rr" "$W" "$_tag" "$W" "$_tag" > "$W/job-$_tag.txt"
  rm -f "$W/shot-$_tag.png" "$W/meta-$_tag.txt"
  USP_JOB="$W/job-$_tag.txt" timeout 550 mono "$CHIMERA/build/Chimera.exe" --headless \
    "--config=$W/config.ini" "--core=$PKGDIR" \
    --firmware "sos128_0.rom=$U/sos128_0.rom" \
    --firmware "sos128_1.rom=$U/sos128_1.rom" \
    --firmware "sos48.rom=$U/sos48.rom" \
    --firmware "service.rom=$U/service.rom" \
    --firmware "dos513f.rom=$U/dos513f.rom" \
    "--lua=$CORE/waterbox/tests/usp-fb.lua" "$TAP" > "$W/log-$_tag.txt" 2>&1
  echo "fe: run $_tag exit=$? frames=$_frames mask=$_mask rerecord=$_rr"
  tail -n 3 "$W/log-$_tag.txt" | cut -c1-160
}

fe_meta() { # <tag> <field>
  sed -n "s/^$2=//p" "$W/meta-$1.txt" | head -n 1
}

echo "fe leg fe-boot: TAP boots through the real session pipeline"
fe_run boot "$FRAMES" 0 "" 0
[ "$(fe_meta boot status)" = "OK" ] || { echo "fe leg fe-boot: FAILED — $(cat "$W/meta-boot.txt" 2>/dev/null || echo NO-META)" >&2; exit 1; }
[ "$(fe_meta boot frames)" = "$FRAMES" ] || { echo "fe leg fe-boot: FAILED — advanced $(fe_meta boot frames), want $FRAMES" >&2; exit 1; }
[ -f "$W/shot-boot.png" ] || { echo "fe leg fe-boot: FAILED — no screenshot" >&2; exit 1; }
[ -n "$(fe_meta boot ram)" ] || { echo "fe leg fe-boot: FAILED — no RAM hash (memory domains not published)" >&2; exit 1; }
echo "fe leg fe-boot: system ZXS, $FRAMES frames, ram=$(fe_meta boot ram | cut -c1-16)..."

echo "fe leg fe-lag: the boot reads input most frames but not all (lag counter works both ways)"
LBL=$(fe_meta boot lag)
case "$LBL" in ''|*[!0-9]*) echo "fe leg fe-lag: FAILED — no numeric lag count (got '$LBL')" >&2; exit 1;; esac
[ "$LBL" -gt 0 ] || { echo "fe leg fe-lag: FAILED — lag is 0: the hook never saw an unread frame (or never runs)" >&2; exit 1; }
[ "$LBL" -lt "$FRAMES" ] || { echo "fe leg fe-lag: FAILED — every frame lagged: the hook never fires" >&2; exit 1; }
echo "fe leg fe-lag: lag=$LBL of $FRAMES (boot pause, then polled every frame)"

echo "fe leg fe-determinism: the same boot twice gives identical machine hashes"
fe_run repeat "$FRAMES" 0 "" 0
[ "$(fe_meta repeat status)" = "OK" ] || { echo "fe leg fe-determinism: FAILED — repeat run not OK" >&2; exit 1; }
[ "$(fe_meta repeat ram)" = "$(fe_meta boot ram)" ] || { echo "fe leg fe-determinism: FAILED — RAM hashes differ" >&2; exit 1; }
[ "$(fe_meta repeat vram)" = "$(fe_meta boot vram)" ] || { echo "fe leg fe-determinism: FAILED — VRAM hashes differ" >&2; exit 1; }
cmp -s "$W/shot-boot.png" "$W/shot-repeat.png" || { echo "fe leg fe-determinism: FAILED — screenshots differ" >&2; exit 1; }
echo "fe leg fe-determinism: ram/vram/shots identical"

echo "fe leg fe-input: Space+Enter held must change the machine (bits 20,21)"
fe_run input "$FRAMES" 3145728 "" 0
[ "$(fe_meta input status)" = "OK" ] || { echo "fe leg fe-input: FAILED — input run not OK" >&2; exit 1; }
[ "$(fe_meta input ram)" != "$(fe_meta boot ram)" ] || { echo "fe leg fe-input: FAILED — input changed nothing (RAM hash identical); the leg has no teeth" >&2; exit 1; }
echo "fe leg fe-input: teeth confirmed (RAM hash differs)"

echo "fe leg fe-rerecord: per-frame save+load must equal the plain run"
fe_run rerecord "$FRAMES" 0 "" 1
[ "$(fe_meta rerecord status)" = "OK" ] || { echo "fe leg fe-rerecord: FAILED — rerecord run not OK" >&2; exit 1; }
[ "$(fe_meta rerecord ram)" = "$(fe_meta boot ram)" ] || { echo "fe leg fe-rerecord: FAILED — rerecord RAM differs" >&2; exit 1; }
[ "$(fe_meta rerecord vram)" = "$(fe_meta boot vram)" ] || { echo "fe leg fe-rerecord: FAILED — rerecord VRAM differs" >&2; exit 1; }
cmp -s "$W/shot-boot.png" "$W/shot-rerecord.png" || { echo "fe leg fe-rerecord: FAILED — rerecord screenshot differs" >&2; exit 1; }
echo "fe leg fe-rerecord: ram/vram/shots equal the plain run"

echo "fe leg fe-keybinds: all 62 declared buttons set at once"
fe_run keybinds "$FRAMES" 4194303 "$P5KEYS" 0
[ "$(fe_meta keybinds status)" = "OK" ] || { echo "fe leg fe-keybinds: FAILED — mnemonic run not OK (a declared name did not resolve)" >&2; exit 1; }
[ "$(fe_meta keybinds ram)" != "$(fe_meta boot ram)" ] || { echo "fe leg fe-keybinds: FAILED — full run identical to plain; the leg has no teeth" >&2; exit 1; }
echo "fe leg fe-keybinds: all 62 buttons resolve, machine differs from plain"

echo "fe: done (all legs green)."
