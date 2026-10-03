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
- **M1 — virtual time.** One seam where the emulator asks the wall what time
  it is; time bought with executed instructions, idle jumps to the next
  deadline. Gate leg stalls the host 300 ms and proves the machine did not
  notice (plus a negative control on the host clock).
- **M2 — guest build.** Same emulator through the musl guest toolchain into
  `core.wbx`. `MINIBOX_DIR=~/chimera/extern/chimera-common-minibox`
  (passed down from `build-package.sh`; never guessed from `$HOME`).

## Editing vs building

Edit here (`Chimera Dev/chimera-core-unrealspeccyp`), build from `~/`
copies. `tools/sync-to-home.sh` does the `cp -a` sync for both this repo
and `Chimera Dev/chimera` → `~/chimera`, then checks `MINIBOX_DIR`.

## Build

```
./waterbox/build-native.sh                                   # M0
./waterbox/run-gate.sh                                       # legs
MINIBOX_DIR=~/chimera/extern/chimera-common-minibox \
  ./waterbox/build-guest.sh                                  # M2
./waterbox/build-package.sh -r ~/chimera                     # everything CI runs
```
