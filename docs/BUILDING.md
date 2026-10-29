# Building chimera-core-unrealspeccyp

Requirements: a C++ compiler, meson, ninja, python3, git. The guest links on
Linux natively, or inside WSL Ubuntu from a Windows checkout. The frontend
gate also needs mono and Xvfb, with Chimera itself built (its engine and its
interface).

Fresh clone to gated package — Chimera is cloned beside the core, because
`build-package.sh` takes its checkout with `-r`:

```
git clone --recursive https://github.com/ToolAssisted-run/chimera ../chimera
git clone https://github.com/CloakTheLurker/chimera-core-unrealspeccyp
cd chimera-core-unrealspeccyp
./waterbox/build-package.sh -r ../chimera
```

That builds the native reference, links `core.wbx` through the musl guest
toolchain, runs the full gate, stamps version/versionDate from the commit,
lays out `dist/licenses/`, and zips
`dist/unrealspeccyp-<sha>.chimeraCore`.

The package is stamped with the commit it was built from. A tree with tracked
modifications builds `-dirty`, one with no git history `+local`; neither is
publishable (see "Publishing" in `README.md`).

What each script does:

- `waterbox/build-native.sh` — headless reference harness
  (`build/native/run-native`).
- `waterbox/build-guest.sh` — needs `MINIBOX_DIR` (passed down from
  `-r <chimera>`); links `build/guest/core.wbx` on Linux, or inside WSL
  Ubuntu via `tools/wsl/guest-build.sh`. Never guesses the toolchain path.
- `waterbox/run-gate.sh` — every leg says what it compared; see
  `docs/PLAN.md`.
- `waterbox/check-wbx.sh` — miniBox guest hygiene (needs `MINIBOX_DIR`).
- `waterbox/tests/run-frontend.sh` — the frontend suite: boot, lag,
  determinism, input, rerecord and keybinds through the real Chimera window,
  headless under mono + Xvfb. It needs `../chimera/build/Chimera.exe` and
  `../chimera/build/dll`.
- `tools/wsl/mb-sync.sh` — copies miniBox to a space-free WSL-native dir
  (musl/libstdc++ configures die on spaces in srcdir/builddir).
- `tools/wsl/guest-legs.sh` — builds `run-wbx` (host driver) and runs it.
- `tools/wsl/guest-build.sh` — the WSL side of the guest link.

Paths: each script derives the core root from its own location.
`CHIMERA_ROOT` overrides where Chimera is (a CI workspace keeps it inside the
core directory). `MINIBOX_DIR` always comes down from `build-package.sh -r`;
`run-gate.sh` only falls back to a sibling `../chimera` checkout.

The guest legs hand files between processes through `GATE_SCRATCH`: under
WSL it defaults to `/var/tmp/chimera-usp-gate` (native ext4 — it survives `wsl -t`, unlike
`/tmp`); on Linux it defaults to `build/guest/scratch`. Set `GATE_SCRATCH` to
move it.

## What CI does

`.github/workflows/chimera.yml` runs on a fresh Ubuntu clone: it checks out
Chimera with submodules, builds miniBox with `-Dguest_cpp=true`, builds
Chimera's engine and interface, then runs `./waterbox/build-package.sh -r
chimera` — the whole gate, frontend included — and uploads the package. A
second job builds Chimera's natives and runs `InstalledCorePackagesTests` and
`MnemonicUniquenessTests` against that package with `CHIMERA_CORES_DIR`.

The ROM/game matrix (`waterbox/tests/run-rom-matrix.sh`) is local-only: it
needs copyrighted content from `ROMs/`, which is gitignored and never on a
runner.

## Troubleshooting (all earned the hard way, all in the scripts now)

- WSL `wsl.exe` sometimes never exits after its script finishes: WSL legs go
  through `waterbox/wsl-call.sh` (launch-and-poll on a log marker, kill the
  hung client, retry). Never `wait` on a Windows PID from msys.
- `wsl.exe -t Ubuntu` WIPES `/tmp`: keep hand-off files on native ext4
  (`/var/tmp/chimera-usp-gate`), never `/tmp`.
- Objects land atomically (`.tmp` + `mv`) so a killed compile is resumable.
- Patch application copies upstream to `build/upstream-patched`
  (marker-skipped) and normalizes CRLF only in touched files;
  `extern/upstream` stays pristine.
- The bundle sends each core's stdout to `/dev/null`; reproduce a silent
  failure with
  `env HOME=/tmp/empty ./waterbox/build-package.sh -r <chimera> > /dev/null`.
  A step that fails in four tenths of a second with no output failed on
  stdout.
- WSL now ships system meson/ninja; the old user-local 1.7 bootstrap is not
  needed.
