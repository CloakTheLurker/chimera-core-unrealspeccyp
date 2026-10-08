# chimera-core-unrealspeccyp — PLAN

Per-core reasoning for the UnrealSpeccyP port. Companion to
`chimera/docs/porting-a-core.md` (the order the work goes in),
`chimera/docs/design-principles.md` (why) and
`chimera/docs/waterbox-analysis.md` (what the sandbox is).

Upstream pin: `0.0.86.30` (`cores/UnrealSpeccyP-0.0.86.30.tar.gz`,
sha256 `8cc28f375c8cfb324fbe72f1f0d403d15f8c4b3c3622b008dcb8b0059fd79579`).

## M0 — skeleton + headless native build (current)

Goal: upstream building headless with no frontend, no host devices, no
window system. Two or three patches (build options) and a stub for whatever
backend picks a platform at compile time.

Findings (all paths relative to `extern/upstream/`):

- Machine core is already separable: `speccy.h` / `speccy.cpp` define
  `eSpeccy` (CPU + memory + devices, `Reset()` / `Update(int* fetches)`),
  with Pentagon timings baked in (`frame_tacts = 71680`, `int_len = 32`).
  `Update(NULL)` advances exactly one frame; `Update(&fetches)` replays a
  count. That is the stepping loop the adapter wraps.
- The handler seam is `platform/platform.h` (`xPlatform::eHandler`: `OnInit`
  / `OnDone` / `OnLoop` / `OnOpenFile` / `VideoData` / audio pulls) with the
  single implementation in `speccy_handler.cpp`. `OnLoop` itself is already
  frame-stepped: one call = `speccy->Update()` + `++video_frame` (replay
  path included). No wall clock inside it.
- There is already a headless platform: `platform/benchmark/`
  (`main_benchmark.cpp`, `USE_BENCHMARK`) drives
  `Handler()->OnInit / OnOpenFile / OnLoop / OnDone` with no window, no SDL,
  no UI. M0 builds on exactly this: core sources (`*.cpp` at root, `z80/`,
  `tools/`, `snapshot/`, `devices/...`, `3rdparty/minizip`,
  `3rdparty/tinyxml2`, vendored `3rdparty/zlib` fallback) +
  `platform/platform.cpp` + `platform/io.cpp` + a POSIX `io_select` + the
  benchmark main, replaced by `waterbox/run-native.cpp` (flags for every
  diagnostic).
- What M0 deliberately leaves out: `USE_SDL` / `USE_SDL2` / `USE_WXWIDGETS`
  / `USE_GL` / `USE_OAL` / `USE_UI` / `USE_CURL` / `USE_WEB`. No `SDL_Init`,
  no `SDL_CreateWindow`, no OpenAL, no wxWidgets. `file_type_zip.cpp` stays
  (format support); networked file selectors under `platform/web/` go.
- Picture without a GPU: `devices/ula.h` — `eUla::Screen()` returns the
  machine-painted framebuffer (`S_WIDTH 320 x S_HEIGHT 240`, ZX area
  `256x192`). `speccy_handler.cpp` already serves it as `VideoData()`.
  This is porting-doc picture option 1 (read the machine's own memory): no
  graphics driver, and the sandbox picture is the reference byte-for-byte
  by construction. Renderer-perturbation check still owed (same game with
  and without the readback, compare instruction counts).
- Audio without a device: `eDeviceSound` pulls (`AudioData` /
  `AudioDataReady` / `AudioDataUse`, three sources: beeper, AY, tape).
  Pulling runs the machine's own callbacks, so the reference harness must
  pull too or native and guest diverge (porting doc section 5).
- `patches/` status: M0 needs **no** upstream patches — the benchmark seams
  already compile out the window system. The series file is intentionally
  empty; patches start at M1 (the time seam). The all-or-nothing applier
  (`waterbox/apply-patches.sh`) is already in place so the rule holds from
  day one.

M0 done when: `waterbox/build-native.sh` produces `build/native/run-native`
with no SDL/GL/window linkage, and `run-native --help` plus a smoke run
(`--frames N`, `--dump-video`, `--pull-audio`, `--trace-instr`) work on a
snapshot/disk image.

## M1 — virtual time (DONE 2026-10-03)

Find the one place the emulator asks the wall what time it is and make it a
seam. Time must be bought with executed instructions; idle must jump to the
next scheduled deadline.

Known wall-clock sites (upstream):

- `platform/sdl2/sdl2.cpp`: `eTick last_tick` +
  `while (last_tick.Passed().Ms() < 15) SDL_Delay(3)` — frame pacing lives
  in the *platform*, not in `OnLoop`. M0 already drops this file; the seam
  must ensure no equivalent creeps into the harness.
- `platform/sdl2/sdl2_audio.cpp` (`UpdateAudio`): audio-full backpressure
  calls `Handler()->VideoPaused(audio_filled)`, which gates `OnLoop`
  (`if (FullSpeed() || !video_paused)`). Real-time audio pacing the machine
  is the second wall clock. M1 replaces it with pull-at-end-of-frame.
- `tools/tick.h` to `platform/linux/tick_gtod.h` (`gettimeofday`) /
  `tools/tick_clock.h` (`clock()`): the tick source itself. The seam wraps
  it so native can run on either a host tick (negative control) or a
  virtual tick derived from `t_states` / `frame_tacts`.
- Tape fast path (`speccy_handler.cpp` `A_TAPE_TOGGLE`,
  `cpu->HandlerStep(fast_tape_emul)`): a speed hack that must be a declared
  setting or gone — it changes what the machine executes.

Gate leg (per porting doc section 1): stall the host 300 ms mid-run and
prove the machine did not notice (identical instruction count / state hash
with and without the stall); then run the same leg on the host clock and
watch it fail. A leg never seen to fail is a leg not tested. Name the test
content (exact file, glob fallback, print which ran).
> Result (gate green): the audit found NO wall clock inside the machine —
> eSpeccy/devices/Z80 timing is purely instruction-counted (t-states/frame,
> TICK_F fixed-point audio resampling, tact-scheduled tape pulses). The only
> wall clocks are the SDL platform pacing (eTick + SDL_Delay) and the audio-
> drain backpressure that gates OnLoop via VideoPaused. So the seam
> (waterbox/usp_time.h) is the pacing layer, not the machine: HostClock vs
> VirtualClock (t_states-derived) plus a FramePacer mirroring the platform
> coupling (pad to wall 20ms; DROP past 100ms lateness, else catch up by stepping unslept). The harness (run-native.cpp) pulls audio+video every
> frame in both flavors; firmware ROMs resolve from in-tree res/rom via
> --resdir or argv[0]. Legs: repeat equal, 300ms stall equal, --clock host
> baseline clean (200/200 stepped, 0 drops) vs stalled 189/200 with 11 drops
> and a different state — teeth confirmed.

## M2 — guest build (IN PROGRESS)

The emulator through the musl guest toolchain, linked into `core.wbx`.
> Progress: the guest link runs on Linux — natively on CI, inside WSL Ubuntu
> from a Windows checkout (meson 1.7 + ninja bootstrapped user-local, no
> root). miniBox's own suite is the foundation gate (`meson test`: musl +
> guest libstdc++ + conformance/thread/cpp guests). Notable: meson marks the
> guest-toolchain custom targets build_by_default=false, so plain `ninja`
> builds only the host — guest-link.sh asks for musl-gcc/emulibc/cxxglue/
> libstdcxx by name. Core-side audit is clean: no throw/threads/iostream/
> RTTI in the guest TU list (only excluded platform files). Entry surface is
> Init()/FrameAdvance/GetVideoBgra/GetVideoRaw/GetAudio/GetAudioBuf/
> GetTStates/GetVsync*; firmware arrives as mounts under bare IDs via patch
> 001 (WBX_GUEST-only hook); input levels are M-later (signature already
> final). Parity vector (tstates/vhash/bhash/mhash/state) is computed by the
> same functions in both flavors (palette.h, Machine::MixedAudio).

- Toolchain comes from `MINIBOX_DIR`
  (`~/chimera/extern/chimera-common-minibox`), passed down from
  `build-package.sh -r <chimera>`; the scripts stop with a message if it is
  absent. No `$HOME` guessing (a runner's `$HOME` is not the checkout), no
  absolute paths in toolchain files.
- Expect the documented traps: no TLS (`-Dthread_local=` etc. +
  `check-wbx.sh` failing on TLS/`%fs`), one thread only (no pools/lazy
  workers), no timed waits (non-blocking takes only), weak symbols forced
  with `-Wl,-u,<name>`, musl `open()` `O_CLOEXEC` second-syscall wrap,
  syscall gaps collected in `waterbox/guest-syscalls.cpp`, arena sizing by
  growing the MMAP arena (`memoryLayoutMiB` in `waterbox.config` is
  `{sbrk, sealed, invisible, plain, mmap}`).
- Debugging: guest faults print `rip=0x36f0...`; the guest links at
  `0x36f00000000`, so `addr2line -f -C -e core.wbx <rip>` names the
  function. gdb on the host driver needs
  `handle SIGSEGV nostop noprint pass` (miniBox uses SIGSEGV for dirty
  tracking). A hang is usually a timed wait. Reproduce on the reference
  first — most "sandbox bugs" are ordinary bugs the sandbox made visible.
- `waterbox.config` is DRAFT: Pentagon 128K, `systemId "ZXS"` (matches
  chimera's ares row), 50 Hz (`vsyncNumerator 50 / Denominator 1`),
  `320x240` buffer, stereo pull audio, Kempston + Sinclair + QAOP bindings
  to confirm, firmware ROM as a named mount to confirm. Two places keep
  vsync in step: the config and `GetVsyncNumerator`/`Denominator`.
  `version`/`versionDate` are stamped by `build-package.sh`, never
  hand-written.

## Later (per porting doc, in order)

3. Machine filesystem: mounts by name only; prefer serving drives from guest
   memory over teaching upstream a VFS (writes become savestate for free).
4. Picture: ULA framebuffer read (option 1) — no Mesa, no GPU bridge.
5. Input/audio as levels: host says what is held this frame; audio pulled at
   frame end, in both flavors.
6. Savestates: rerecord leg (save/load every frame) + session leg (save in
   one process, load in another). `StateLoaded()` only if something derived
   lives in `alloc_invisible`.
7. Package: keybinds, `file_slots.json` (game as project, machine ROM as
   firmware), `package-licenses.json` (GPL-3.0 upstream + everything linked
   in; currently no Mesa).
8. Speed if needed: measure first.

## Publishing (checklist, from porting doc)

1. Push `ToolAssisted-run/chimera-core-unrealspeccyp`, branch `main`.
2. `chimera.yml`: gate the package on a public runner, upload artifact
   `unrealspeccyp-${{ github.sha }}`. Gate content must be distributable
   (machine-is-its-own-content? upstream test suite? else build +
   sandbox-clean only, honestly claimed). Always run chimera's contract
   tests with `CHIMERA_CORES_DIR` pointed at the package.
3. `publish` job + daily `schedule:` calling
   `ToolAssisted-run/chimera/.github/workflows/publish-core.yml@main`.
4. Row in chimera's `official-cores.json` + README core table
   (`id "unrealspeccyp"`, systems `["ZXS"]`).
