# chimera-core-unrealspeccyp

UnrealSpeccyP (Pentagon 128K ZX-Spectrum) as a Chimera waterbox core.

Upstream: djdron/UnrealSpeccyP, pinned to `0.0.86.30`
(`cores/UnrealSpeccyP-0.0.86.30.tar.gz`, sha256
`8cc28f375c8cfb324fbe72f1f0d403d15f8c4b3c3622b008dcb8b0059fd79579`),
vendored at `extern/upstream/` (never edited in place — see `patches/`).

License: GPL-3.0-or-later (upstream is GPL-3.0; the adapter in `waterbox/`
is under the same terms so the linked core stays distributable as one work).
See `waterbox/package-licenses.json` and `extern/upstream/LICENSE`.

## Layout (per `chimera/docs/porting-a-core.md`)

- `extern/upstream/` — clean upstream tree, pinned, never edited in place.
- `patches/` — numbered series, applied all-or-nothing by
  `waterbox/apply-patches.sh`.
- `waterbox/` — the adapter, the builds, the gate:
  `machine.{h,cpp}`, `wbx-entry.cpp`, `run-native.cpp`, `run-wbx.c`,
  `run-gate.sh`, `waterbox.config`, `file_slots.json`,
  `package-licenses.json`.
- `docs/PLAN.md` — milestones and the reasoning behind every decision.

## Milestones

- **M0 — skeleton + headless native build.** Upstream builds with no
  frontend, no host devices, no window system. `waterbox/build-native.sh`.
- **M1 — virtual time (DONE 2026-10-03, gate green).** The seam is the pacing layer (no wall clock in the machine); one seam where the emulator asks the wall what time
  it is; time bought with executed instructions, idle jumps to the next
  deadline. Gate leg stalls the host 300 ms and proves the machine did not
  notice (plus a negative control on the host clock).
- **M2 — guest build (DONE 2026-10-08, gate green).** Same emulator through
  the musl guest toolchain into `core.wbx` (670KB, hygiene-clean, bit-identical
  parity with native over 600 firmware frames).
  `MINIBOX_DIR=../chimera/extern/chimera-common-minibox`
  (passed down from `build-package.sh`; never guessed from `$HOME`).
- **M3 — input levels + savestates (DONE 2026-10-26, gate green).** 2-byte
  input levels (Kempston + Space/Enter) applied identically in both flavors;
  rerecord + two-process session savestate legs green.

- **M4 — the package (DONE 2026-10-27, unofficial core).** Real engine ABI
  (`FrameAdvance(uint64_t)` + `SetButton`), 22 declared buttons with
  mnemonics, settings that reach the machine (mode48k/fastTape/soundChip),
  5 firmware ROMs with sizes + SHA1s, `default_keybinds.json`, current-schema
  `package-licenses.json`, zipped `.chimeraCore`. Gate green; Chimera's
  contract tests 26/26. No roster row, no publish job (unofficial).

## Editing vs building

Edit here (`Chimera Dev/chimera-core-unrealspeccyp`); the guest links on
Linux natively, or inside WSL Ubuntu via `tools/wsl/` (see
docs/BUILDING.md). `build-package.sh -r` takes the sibling `chimera`
checkout; `MINIBOX_DIR` (`chimera/extern/chimera-common-minibox`) is passed
down from it — never guessed from `$HOME`, no absolute paths in scripts.

## Build

```
./waterbox/build-native.sh                     # M0
./waterbox/run-gate.sh                         # legs
./waterbox/build-package.sh -r ../chimera      # everything CI runs
```
