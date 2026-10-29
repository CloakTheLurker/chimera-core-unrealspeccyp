# AGENTS.md — chimera-core-unrealspeccyp

UnrealSpeccyP (Pentagon 128K ZX-Spectrum) as a Chimera waterbox core.
Upstream 0.0.86.30 vendored at `extern/upstream/` (never edited in place;
`patches/` apply onto a build copy via `waterbox/apply-patches.sh`).

Unofficial core: no roster row, no publish job. A release is cut by hand from
a green CI run's artifact (README.md, "Publishing").

## Layout

- `waterbox/` — adapter + builds + gate: `machine.{h,cpp}`, `wbx-entry.cpp`
  (guest ABI), `run-native.cpp`, `run-wbx.c`, `usp_time.h`, `palette.h`,
  `build-{native,guest,package}.sh`, `run-gate.sh`, `check-wbx.sh`,
  `guest-link.sh`, `guest-syscalls.cpp`, and the four declarations
  (`waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json`).
- `waterbox/tests/` — the frontend suite (`run-frontend.sh`), its Lua
  scripts, the distributable test content's generators, and the local-only
  ROM matrix.
- `tools/wsl/` — the WSL legs (guest link, host driver runs, miniBox mirror)
  and `env.sh`, which derives every path from the caller's location.
- `docs/PLAN.md` — milestones and the reasoning behind every decision.
- `docs/BUILDING.md` — requirements, fresh-clone steps, CI, troubleshooting.
- `LICENSE.md` + `COPYING` — what the licence covers (the ROM images in
  `extern/upstream/res/rom/` are not covered), and the GPL's full text.

## Commands (in order)

```
./waterbox/build-native.sh                     # headless reference
MINIBOX_DIR=../chimera/extern/chimera-common-minibox ./waterbox/build-guest.sh
./waterbox/run-gate.sh                         # every leg says what it compared
./waterbox/build-package.sh -r ../chimera      # everything CI runs
CHIMERA_CORES_DIR=<dist> dotnet test <Chimera.Tests.Client.Common> -c Release --filter "FullyQualifiedName~InstalledCorePackagesTests|FullyQualifiedName~MnemonicUniquenessTests"
```

`build-package.sh` builds what it needs and stamps the commit; a tree with
tracked modifications stamps `-dirty`, which is not publishable. The frontend
leg needs Chimera built (engine and interface), mono and Xvfb. Guest legs
stage files in `GATE_SCRATCH` (under WSL `/var/tmp/chimera-usp-gate`, on Linux
`build/guest/scratch`).

## Rules

- The engine contract is law: `FrameAdvance(uint64_t)` (button i = bit i
  of `input.buttons`), optional `SetButton(int,int)`. Check
  `chimera/source/gui/Chimera.Emulation.Common/Waterbox/` before inventing.
- Button order in `waterbox.config` is the movie contract: NEVER reorder.
  There are 62 (four presets × 5, Space/Enter, the 40-key Spectrum keyboard).
- Input is levels, not events, applied whole every frame in both flavors.
- A leg that has never been seen to fail is a leg that has not been tested.
- No absolute paths, no `$HOME` in build scripts (`MINIBOX_DIR` comes down
  from `build-package.sh -r`; `env.sh` derives the rest). Quote every path
  (spaces are load-bearing).
- CI is a fresh Linux clone and runs the whole gate, frontend included. What
  it cannot run is the ROM/game matrix; say so when reporting.
- Commits: subject `type(scope): what changed`; body what changed, why, and
  how it was tested, with the numbers. Stage explicit paths.
