# Building chimera-core-unrealspeccyp

Requirements: a C++ compiler, meson, ninja, python3, git. The guest links on
Linux: natively there, or inside WSL Ubuntu from a Windows checkout
(meson 1.7 + ninja bootstrapped user-local in M2 are no longer needed —
WSL now ships system meson/ninja).

Fresh clone to gated package (paths relative to the Chimera Dev parent,
which also holds the `chimera` checkout with its submodules):

```
./waterbox/build-package.sh -r ../chimera
```

That builds the native reference, links `core.wbx` through the musl guest
toolchain, runs the full gate (`waterbox/run-gate.sh`), stamps
version/versionDate from the commit, lays out `dist/licenses/`, and zips
`dist/unrealspeccyp-<sha>.chimeraCore`.

What each script does:

- `waterbox/build-native.sh` — headless reference harness (`build/native/run-native`).
- `waterbox/build-guest.sh` — needs `MINIBOX_DIR` (passed down from
  `-r <chimera>`); links `build/guest/core.wbx` on Linux, or inside WSL
  Ubuntu via `tools/wsl/guest-build.sh`. Never guesses `$HOME`.
- `waterbox/run-gate.sh` — every leg says what it compared; see docs/PLAN.md.
- `waterbox/check-wbx.sh` — miniBox guest hygiene (needs `MINIBOX_DIR`).
- `tools/wsl/mb-sync.sh` — copies miniBox to a space-free WSL-native dir
  (musl/libstdc++ configures die on spaces in srcdir/builddir).
- `tools/wsl/guest-legs.sh` — builds `run-wbx` (host driver) and runs it.

Troubleshooting (all earned the hard way, all in the scripts now):

- WSL `wsl.exe` sometimes never exits after its script finishes: WSL legs
  go through `waterbox/wsl-call.sh` (launch-and-poll on a log marker, kill
  the hung client, retry). Never `wait` on a Windows PID from msys.
- `wsl.exe -t Ubuntu` WIPES `/tmp`: keep hand-off files on native ext4
  (`/home/cloak`), never `/tmp`.
- Objects land atomically (`.tmp` + `mv`) so a killed compile is resumable.
- Patch application copies upstream to `build/upstream-patched` (marker-
  skipped) and normalizes CRLF only in touched files; `extern/upstream`
  stays pristine.
