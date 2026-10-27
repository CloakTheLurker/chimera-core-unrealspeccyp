# AGENTS.md — chimera-core-unrealspeccyp

UnrealSpeccyP (Pentagon 128K ZX-Spectrum) as a Chimera waterbox core.
Upstream 0.0.86.30 vendored at `extern/upstream/` (never edited in place;
`patches/` apply onto a build copy via `waterbox/apply-patches.sh`).

## Layout

- `waterbox/` — adapter + builds + gate: `machine.{h,cpp}`, `wbx-entry.cpp`
  (guest ABI), `run-native.cpp`, `run-wbx.c`, `usp_time.h`, `palette.h`,
  `build-{native,guest,package}.sh`, `run-gate.sh`, `check-wbx.sh`,
  `guest-link.sh`, `guest-syscalls.cpp`, and the four declarations
  (`waterbox.config`, `file_slots.json`, `default_keybinds.json`,
  `package-licenses.json`).
- `docs/PLAN.md` — milestones and the reasoning behind every decision.
- `docs/BUILDING.md` — requirements and troubleshooting.
- `tools/wsl/` — WSL legs (guest link, host driver runs, miniBox mirror).

## Commands (in order)

```
./waterbox/build-native.sh                     # headless reference
MINIBOX_DIR=../chimera/extern/chimera-common-minibox ./waterbox/build-guest.sh
./waterbox/run-gate.sh                         # every leg says what it compared
./waterbox/build-package.sh -r ../chimera      # everything CI runs
CHIMERA_CORES_DIR=<dist> dotnet test <Chimera.Tests.Client.Common> -c Release --filter "FullyQualifiedName~InstalledCorePackagesTests|FullyQualifiedName~MnemonicUniquenessTests"
```

## Rules

- The engine contract is law: `FrameAdvance(uint64_t)` (button i = bit i
  of `input.buttons`), optional `SetButton(int,int)`. Check
  `chimera/source/gui/Chimera.Emulation.Common/Waterbox/` before inventing.
- Button order in `waterbox.config` is the movie contract: NEVER reorder.
- Input is levels, not events, applied whole every frame in both flavors.
- A leg that has never been seen to fail is a leg that has not been tested.
- No absolute paths, no `$HOME` in build scripts (`MINIBOX_DIR` comes down
  from `build-package.sh -r`). Quote every path (spaces are load-bearing).
- Unofficial core: no roster row, no publish job (see `.github/workflows/chimera.yml`).
