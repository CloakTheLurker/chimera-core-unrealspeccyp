# chimera-core-unrealspeccyp

UnrealSpeccyP (Pentagon 128K ZX-Spectrum) as a [Chimera](https://github.com/ToolAssisted-run/chimera)
waterbox core. It produces one file, `unrealspeccyp-<version>.chimeraCore`,
that goes in Chimera's `Cores` folder.

Upstream: djdron/UnrealSpeccyP, pinned to `0.0.86.30`
(`cores/UnrealSpeccyP-0.0.86.30.tar.gz`, sha256
`8cc28f375c8cfb324fbe72f1f0d403d15f8c4b3c3622b008dcb8b0059fd79579`),
vendored at `extern/upstream/` (never edited in place — see `patches/`).

**This is an unofficial core.** It is not in Chimera's `official-cores.json`,
nothing publishes it automatically, and Chimera downloads nothing itself.
Releases are cut by hand from a green CI run (see [Publishing](#publishing)).

## Install

1. Download the `.chimeraCore` file from this repository's **Releases**.
2. Put it in Chimera's `Cores` folder (**File > Core Manager** shows where
   that is).
3. Put the firmware ROMs Chimera asks for in its firmware folder (below).

## What you bring

The package declares five firmware files by name, size and SHA1. It does not
contain them; Chimera reads them from its own firmware folder:

| file | what it is |
|---|---|
| `sos128_0.rom` | Pentagon 128K BASIC ROM (page 0) |
| `sos128_1.rom` | Pentagon 128K editor/menu ROM (page 1) |
| `sos48.rom` | 48K BASIC ROM (always loaded) |
| `service.rom` | service/test ROM (the 128K menu) |
| `dos513f.rom` | TR-DOS 5.13F for the Beta Disk interface |

The same files are in `extern/upstream/res/rom/` in this repository, because
upstream is vendored verbatim and the gate boots them; copy them from there
if you have no other copy. See `LICENSE.md` for what their terms are.

A program is a tape (`.tap`, `.tzx`, `.csw`), a snapshot (`.sna`, `.z80`,
`.szx`), or a ZIP holding one of those. With none, the machine boots to its
menu or BASIC.

## Machines and settings

- **ZX Spectrum 128K** — the Pentagon 128K: 128 BASIC, the 128K menu, AY
  sound, TR-DOS ROM available (no disk format is declared yet).
- **ZX Spectrum 48K** — 48 BASIC.

Three settings shape the machine, so each is recorded in the project and a
movie replays with the same one:

- **Machine** — 128K or 48K. A snapshot says which machine it was taken on
  and wins.
- **Fast tape loading** — trap the ROM tape loader instead of executing it
  (upstream default). Off is cycle-exact loading, in real time.
- **Sound chip** — AY-3-8910 or YM2149F (different volume tables).

Lag frames are counted: a frame in which the machine never read input is a
frame nobody polled.

## Buttons

62 buttons, in a frozen order (the order is the movie contract):

- **Kempston**, **Sinclair**, **Cursor** and **QAOP** — Up, Down, Left,
  Right and Fire each. The presets are upstream's own key mappings.
- **Key.Space** and **Key.Enter** — the two keys a tape loader needs.
- **The Spectrum keyboard** — all 40 keys, one button each, including Caps
  Shift and Symbol Shift.

The default bindings are in
[`waterbox/default_keybinds.json`](waterbox/default_keybinds.json): Kempston
on the arrows and X, QAOP on Q/A/O/P/M, Space and Enter, and the keyboard
1:1. Sinclair and Cursor are picked in Chimera's controller config. Both
Shift keys send `Shift`, so Caps Shift and Symbol Shift both answer it
(rebind them separately to split them).

## Status

The gate is green end to end, and Chimera's contract tests pass against the
built package. Tried with Manic Miner, Driar and EXO-TICAL: picture, stereo
sound, tapes, keys, joysticks, snapshots and savestates work, and the
sandboxed core gives the same results as the plain native build.

Not there yet:

- no disk formats declared (the TR-DOS ROM is declared, but a `.trd`/`.dsk`
  cannot be opened);
- no per-game settings (the in-game key presets are picked by hand);
- one content file per project;
- No Kempston mouse or other add-on interfaces.

## Build

Requirements: a C++ compiler, meson, ninja, python3, git; for the frontend
gate also mono and Xvfb, with Chimera built. The guest links on Linux
natively, or inside WSL Ubuntu from a Windows checkout. Fresh clone to gated
package, with Chimera's checkout beside it:

```
git clone --recursive https://github.com/ToolAssisted-run/chimera ../chimera
./waterbox/build-package.sh -r ../chimera
```

That builds the native reference, links `core.wbx` through the musl guest
toolchain, runs the full gate, stamps version/versionDate from the commit,
lays out `dist/licenses/`, and zips
`dist/unrealspeccyp-<sha>.chimeraCore`.

What each script does, the WSL notes, and the traps that cost days are in
[docs/BUILDING.md](docs/BUILDING.md). The design log — every milestone, every
decision and its measurement — is [docs/PLAN.md](docs/PLAN.md).

## Publishing

Unofficial: there is no publish job and no schedule. To cut a release, take
the artifact from a green CI run (or a package built from a clean checkout at
the commit), check that the `waterbox.config` inside stamps that commit and
no `-dirty`, and create a GitHub release by hand:

- tag `dev` for the rolling build (pre-release, replaced next time by
  deleting the release and its tag), or `nightly-YYYY-MM-DD` for an immutable
  dated one;
- asset named `unrealspeccyp-<sha>.chimeraCore`;
- notes that say what changed, what the user must bring, and what was not
  proved.

A package built from a tree with tracked modifications stamps `-dirty`, and
one with no git history stamps `+local`; neither is publishable.

## Milestones

- **M0 — skeleton + headless native build.**
- **M1 — virtual time (DONE 2026-10-03).** The seam is the pacing layer; a
  300 ms host stall does not move the machine.
- **M2 — guest build (DONE 2026-10-08).** `core.wbx` is 670KB, hygiene-clean,
  and bit-identical to the native build over 600 frames.
- **M3 — input levels + savestates (DONE 2026-10-26).** Rerecord and
  two-process session legs green.
- **M4 — the package (DONE 2026-10-27).** The engine ABI, buttons, settings,
  firmware, keybinds and licences; Chimera's contract tests 26/26.
- **M5 — content loading + frontend gate (DONE 2026-10-27).** Distributable
  test content, tapes and snapshots, the real frontend boots it headless.

## Licence

GPL-3.0-or-later; the full text is in [COPYING](COPYING), and
[LICENSE.md](LICENSE.md) says what it covers, what the package contains, and
what it does not cover (the ROM images).
