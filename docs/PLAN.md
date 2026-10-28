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

## M2 — guest build (DONE 2026-10-08)

The emulator through the musl guest toolchain, linked into `core.wbx`.
> DONE: gate green end to end (run-gate.sh EXIT=0). core.wbx (670KB)
> links through the musl + guest-libstdc++ toolchain at 0x36f00000000,
> passes miniBox check-wbx.sh (no TLS, no %fs, nothing below rsp), and the
> parity leg holds bit-identical: native vs guest agree on tstates (43008000),
> vhash, bhash, mhash and state (9a27884bfbb37739) over 600 firmware frames.
> No guest traps fired: no TLS/RTTI/exceptions/threads in the TU list, no
> syscall gaps on the firmware-boot path (fopen/fread on mounts works),
> static constructors (audio filter tables) run in the guest. Hard-won
> environment lessons (all in the scripts now): meson marks guest-toolchain
> targets build_by_default=false (ask by name); partial GCC/tar states from
> killed runs need repair (tools/wsl/fix-gcc-src.sh, pre-verified fetch);
> patches apply onto a marker-skipped build copy (CRLF-normalized); the link
> needs the musl specs on the link line (host crt leaks in otherwise);
> wsl.exe intermittently never exits after its script finishes — WSL legs go
> through wsl-call.sh (launch-and-poll on a log marker, absolute taskkill
> path, no msys wait on Windows PIDs) and objects land atomically so kills
> are resumable.
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

## M3 — input levels + savestates (DONE 2026-10-26)
> DONE 2026-10-26, gate green end to end. Input is levels: byte0 Kempston
> (bit0 Right, bit1 Left, bit2 Down, bit3 Up, bit4 Fire) + byte1 keys (bit0
> Space, bit1 Enter), applied whole every frame via Machine::SetInputMask in
> BOTH flavors (native --input-mask/--input-keys += from/to; guest
> FrameAdvance decodes the same bytes). Teeth: Space+Enter over 600 firmware
> frames perturbs the machine (state differs); parity: guest-with-input ==
> native-with-input. Savestates: rerecord leg (save+load around EVERY frame
> == plain run) and session leg (save at 299 in one process, continue 300 in
> another: tstates + last-frame video/audio lvhash/lmhash equal the
> uninterrupted run) both green. No traps: kbd/joy OnKey calls are
> idempotent levels, no new syscalls (fopen/fread on mounts only).
> Environment lessons: musl/libstdc++ configures die on spaces in
> srcdir/builddir — minibox now builds in a WSL-native space-free mirror
> (tools/wsl/mb-sync.sh; guest-link consumes MB_SRC_DIR/MB_BUILD_DIR, CI
> keeps the checkout-defaults path); WSL wsl.exe -t WIPES /tmp, so the
> session state file lives at /home/cloak (the retry -t was deleting its own
> evidence); wsl_call preserves per-attempt logs for post-mortem.

Porting-doc mapping: item 4 (picture) was already done in M2 (ULA framebuffer read, parity holds); item 5 input is done here (audio pull was M1/M2); item 6 savestates done here (no StateLoaded needed — nothing derived lives in alloc_invisible). Item 3 (machine filesystem) needs no work for firmware boot: ROMs mount by name, no writable drives yet. Remaining: item 7 package + publishing checklist.

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

## M4 — the package (unofficial core)

Unofficial: no roster row, no publish job (`.github/workflows/chimera.yml`
is gate + contract tests only). Everything else in the porting-doc package
step still applies: the declarations must be honest and the contract tests
must pass, because the frontend believes the declarations.

- Guest ABI fix (load-bearing): the engine calls `FrameAdvance(uint64_t)`
  with button i = bit i of `input.buttons`, and optional `SetButton(int,int)`
  deltas. The old 2-arg byte-pointer export would have failed to load under
  the real engine (`proc("FrameAdvance", 1)`). `Machine::ApplyMask` is the
  one input path in both flavors; `SetButtonByIndex` serves the delta export.
- Buttons (22, order frozen — movie contract): Kempston, Sinclair (=upstream
  SINCLAIR2 map 6/7/8/9/0), Cursor (=upstream CURSOR map 7/6/5/8/0), QAOP
  (=upstream QAOPM map Q/A/O/P/M), Key.Space, Key.Enter. All presets are
  upstream's own key mappings from `speccy_handler.cpp`; nothing invented.
  Mnemonics: 22 distinct printable ASCII (contract test demands one letter
  per button, unique per controller).
- Settings (read in guest Init from the mounted settings JSON; same
  `Machine::Configure` path in the native harness behind flags): mode48k
  (bool), fastTape (bool, default on = upstream default), soundChip (enum
  ay/ym). fastTape mirrors upstream exactly: step installed only while a
  tape runs (delay-loop acceleration must never fire outside tape loads).
  No tape content exists yet, so the step is a no-op in every leg so far.
- Firmware: the 5 ROMs the loader asserts on, with sizes + uppercase SHA1s.
  sos48.rom is always loaded (only *selected* in 48K mode).
- file_slots.json: `formats` (not `extensions`), min 0 (bare BASIC boot is
  valid — the gate proves it), max 1, game slot.
- default_keybinds.json: Kempston on arrows+X, QAOP on its letters,
  Space/Enter; Sinclair/Cursor unbound (picked in controller config).
- package-licenses.json in the current schema (effectiveTerms
  GPL-3.0-or-later, commercial use allowed): upstream GPL, tinyxml2/zlib,
  minizip+zlib (always linked), miniBox MIT kit, guest libstdc++ (exception),
  adapter GPL. Texts vendored under waterbox/licenses/.
- build-package.sh now stamps version/versionDate, lays out licenses/ via
  package-licenses.py, and zips dist/unrealspeccyp-<sha>.chimeraCore.
- Contract tests (CHIMERA_CORES_DIR=dist): 26/26 pass locally
  (InstalledCorePackagesTests + MnemonicUniquenessTests).
- Repo hygiene per new-core.md §3: docs/BUILDING.md, AGENTS.md, CI at
  .github/workflows/chimera.yml (root chimera.yml was never an Actions
  path — moved).
- Deferred: frontend gate (needs a real frontend run), per-game settings
  (SuggestSettings/GetGameSettings — needs game content to be honest about).

## M5 — content loading + frontend gate (DONE 2026-10-27)

Test content is hand-built and distributable (no copyrighted bytes):
test-content/boot.tap (a `10 REM` program; generator tests/make-boot-tap.py)
and test-content/boot48.sna (48K snapshot booting to BASIC; generator
tests/make-boot48-sna.py). The machine ROMs they boot are the declared
firmware, mounted separately. tape auto-load exercises the guest tape path
end to end; the snapshot exercises xSnapshot::Load.

- Load path: native and guest share one (`Machine::OpenFile` ->
  adapter-owned `OpenGameFile` in waterbox/file-types.cpp), calling the
  same upstream entry points the UI handler's versions call
  (eTape::Open, xSnapshot::Load) minus the UI parts. speccy_handler.cpp
  (own eHandler + macros) is excluded from both builds; the stale-object
  segfault it caused is why build-native.sh/guest-link.sh now force a full
  rebuild when the TU list changes (script/series/pin marker).
- Game discovery: the engine mounts the game at romFile ("rom", was
  "core.wbx"), the same bytes under "/basename", and the name in
  "rom.name"; run-wbx --game mounts all three and guest Init tries
  bare, /bare, then romFile (project mounts need the bare spelling).
- file_slots.json formats trimmed to what loads: tap,tzx,csw,sna,z80,szx,zip.
- waterbox.config gained the extension->ZXS map (without it every
  directly-opened file falls into the platform chooser, fatal headless).
- Guest ABI corrections from the first real frontend boot: memory domains
  are mandatory (RAM = 8 consecutive pages, read-write; VRAM = ULA screen,
  read-only), and the engine calls GetVideoBgra/GetAudio with NO arguments
  (pointer back; size from GetVideoWidth/Height and GetAudioSampleCount).
  The old (w,h,buf) exports wrote through host pointers — a sandbox
  violation that only the frontend run could show (run-wbx passed NULLs).
- Parity bug the SNA leg caught: run-wbx capped the audio hash at 882 pairs
  while native hashes the full frame-0 mix (a snapshot load flushes ~882
  extra samples in). GetAudioSampleCount now returns the true count (the
  engine caps playback itself); the driver hashes exactly what native
  hashes. Per-frame fhash probes showed the core was bit-identical all
  along; only the driver's accounting lied.
- Gate m5 legs: TAP content rides every m2/m3 leg (guest takes --game as a
  space-free basename staged under the guest build dir — the WSL
  trampoline cannot carry spaced paths); SNA parity/repeat/input-teeth+parity/
  settings-parity follow.
- Frontend suite (waterbox/tests/run-frontend.sh via tools/wsl/fe-gate.sh,
  mono+Xvfb, package dir + positional rom): boot (system ZXS, 600 frames,
  RAM/VRAM hashes), determinism (hashes+shots identical), input teeth
  (Space+Enter change the RAM hash — screenshots are blind to keyclicks,
  so the teeth compare memory, proven by probe), rerecord, keybinds (all
  22 mnemonics resolve live). joypad.set lands (probe showed get() state)
  because the GUI frame loop consumes overrides around frameadvance.
- Full gate green end to end; contract tests 26/26 on the fresh package.
- Still deferred: per-game settings (SuggestSettings/GetGameSettings).

## Firmware hashes + Manic Miner matrix (2026-10-27, on top of M5)

- The five firmware SHA1s in waterbox.config were corrupted hand
  transcriptions (dropped characters); sizes matched, so every file graded
  Unrecognised ("a dump the core has never seen") while the core booted
  fine (it never checks hashes — only the frontend survey does). Fixed by
  stamping all five programmatically from extern/upstream/res/rom/ and
  verifying GOOD. Lesson: hashes are never typed by hand.
- waterbox/tests/run-rom-matrix.sh (local-only, never CI — ROMs/ is
  gitignored, copyrighted files stay untracked): each given game × all 8
  sync combos, native vs guest parity on state+tstates+vhash+bhash+mhash.
  Manic Miner .tap + .sna: all 16 parities green; mode48k moves the TAP
  (teeth), the SNA's devices come from the image (parity is the assertion).
  NOTE: inserted tapes do not auto-load (nothing types LOAD ""); the SNA is
  the leg that executes real game code. A Manic Miner SNA + Kempston spot
  check later confirmed game input parity too (native==guest, states diverge
  from plain when Kempston is held).

## 128K boot page + keyboard controller + column groups (2026-10-27)

- 128K firmware boot stranded in the service ROM: eRom::Reset leaves ROM_SYS
  mapped and nothing selected the SOS page. Upstream A_RESET selects
  ROM_128_1 when not in 48K mode — Machine::Reset now mirrors it (tape and
  snapshot paths select their own page right after, unchanged). Proven by
  screenshot: 128K menu (Tape Loader/128 BASIC/Calculator/48 BASIC/TR-DOS)
  vs 48 BASIC. Gate leg m4-boot-pages pins both firmware vhashes (pre-fix
  128K vhash 844eda67... was the service screen).
- Keyboard controller: P5, the full 40-key matrix in upstream eKeyboard
  order (bits 22-61; total 62 <= 64). Key.Space/Key.Enter (bits 20/21)
  alias P5 Space/Enter.
- Columns group by type via P<n> prefixes (the only grouping mechanism):
  P1 Kempston, P2 Sinclair, P3 Cursor, P4 QAOP, P5 keyboard, console
  Key.Space/Key.Enter. Bit order of the first 22 is untouched (movie
  contract); mnemonics kept per group (U/D/L/R/F, u/d/l/r/f, ^/v/</>/*,
  QAOPM, S/E) with P5 keycaps (0-9A-Z_=^&).
- Real bug the alias legs caught: preset buttons alias P5 keys, and the old
  last-writer-wins ApplyMask released a key another button still held
  (bit15 Q killed by unheld bit32). ApplyMask now ORs every upstream key
  across all buttons driving it. Gate m6 legs prove P5 Q == QAOP Q and
  P5 Space == Key.Space natively, with guest parity; the legs fail on the
  old code (observed Q15==plain while Q32 perturbed).
- Driver --input-mask is now full 64-bit (was masked to Kempston bits);
  frontend keybinds leg holds all 62 (P5 by whole name, past Lua's float
  range for bit math). default_keybinds: renamed presets + 1:1 keyboard
  (Number0-9, letters, Space, Enter, merged Shift).

## Tape autostart, Symbol Shift, grouped names, typed LOAD (2026-10-28)

- Tapes never moved: nothing ever called eTape::Start (upstream relies on a
  UI play button + tape macro the headless core has no room for). Worse, the
  reset inside FileTypeTape::Open stopped the tape that Open had just
  started. Now Open starts the tape AFTER its Reset (a finished tape stays
  finished, like a real deck). Seen in mhash the moment it landed.
- Symbol Shift never worked: Machine::ApplyMask passed hardwired
  shift=false/alt=false to eKeyboard::OnKey, whose contract clears both
  shifts on every call — a held P5 Shift was released by the same call that
  set it. Now the ORed Caps/Symbol levels ride every OnKey call (the real
  semantic: shifts are modifiers of the same read). Verified by typing
  PRINT "A" (prints A + 0 OK) and by loading a tape whose name needs quotes.
- Found together with a test-bit typo (my --type mapped '"' to bit 59/'M'
  instead of 58/Symbol): the m6 alias legs pin the real mapping by equating
  P5 Q/Space with the trusted QAOP/Space keys in both flavors.
- waterbox/tests/typeload.txt types J "" + Enter (J is the LOAD keyword;
  4f hold/12f period from frame 100, inside the header pilot). Gate leg
  m6-tape-load (+cycle-exact variant with fastTape off): teeth are a state
  change vs plain TAP; the fast-load vhash is pinned to the known-good
  loaded screen (Program: boot ... 0 OK, 10:1, verified visually), guest
  must match it too.
- Column groups are named after controller type, not player number:
  waterbox.config input gained optional "playerNames" (1 Kempston, 2
  Sinclair, 3 Cursor, 4 QAOP, 5 Keyboard); Chimera renders those in
  TAStudio's column menu instead of "Player n" (WaterboxConfig.InputConfig,
  ControllerDefinition, WaterboxCore.MakeControllerDefinition,
  TAStudio.MenuItems; unknown keys are ignored, so old packages are fine).

## Lag frames + display name (2026-10-28, on top of the above)

- Lag frames, following chimera-core-fuse: patches/002-input-was-read.patch
  sets a guest flag in eKeyboard/eKempstonJoy IoRead (native builds compile
  it out via WBX_GUEST); wbx-entry clears it per FrameAdvance and exports
  InputWasRead; waterbox.config declares lag.inputWasRead. The frontend
  REQUIRES the export when declared (aborts without it), so a missing hook
  fails boot, loudly. Frontend leg fe-lag asserts 0 < lagcount < frames on
  the TAP boot (measured 80/600: boot ROM init doesn't poll, then every
  frame does) — teeth in both directions.
- systemNames {"ZXS": "ZX Spectrum"} (same pattern as fuse): the display
  name for the system; the id stays ZXS (movie/project compat).
