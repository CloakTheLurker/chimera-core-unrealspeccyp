Portable ZX-Spectrum emulator core for Chimera.
Copyright (C) 2026 the chimera-core-unrealspeccyp authors.

This repository, and the package it builds, is free software under the GNU
General Public License, version 3 or later. The full text is in `COPYING`
(and in `extern/upstream/gpl-3.0.rtf`, as upstream ships it).

## What this licence covers

- The adapter, the harnesses, the gate and the build scripts under
  `waterbox/`, the numbered patches under `patches/`, and the documents in
  this repository: GPL-3.0-or-later, the same terms as the upstream they
  link.

## What it builds from

- **UnrealSpeccyP**, the emulator, pinned to `0.0.86.30` and vendored
  verbatim at `extern/upstream/` (never edited in place; `patches/` apply to
  a build copy). Upstream is GPL-3.0-or-later, at
  <https://github.com/djdron/UnrealSpeccyP>. The package's `core.wbx` is
  upstream's emulation plus this repository's adapter, and is distributed
  under the same terms as one work.
- **tinyxml2** and **minizip + zlib**, vendored inside upstream's
  `3rdparty/` and linked into `core.wbx`: zlib licence.
- **the miniBox guest kit** (musl libc + emulibc), the toolchain the guest
  is built with: MIT.
- **GNU libstdc++ 13**, the guest C++ standard library: GPL-3.0-or-later
  with the GCC Runtime Library Exception 3.1.

The built `.chimeraCore` carries the texts above under `licenses/`, with
`licenses.json` naming each component. `waterbox/package-licenses.json` is
where it is computed from.

## What it does not cover

The ROM images under `extern/upstream/res/rom/` are not part of the GPL
grant. They are the ROMs UnrealSpeccyP is distributed with (the Spectrum's
ROMs belong to Amstrad, which allows them to be distributed with emulators;
TR-DOS belongs to its authors). They are in this repository because upstream
is vendored verbatim and because the gate boots them.

The built package does **not** contain them. It declares the five files by
name, size and SHA1, and Chimera reads them from its own firmware folder:
`sos128_0.rom`, `sos128_1.rom`, `sos48.rom`, `service.rom`, `dos513f.rom`.
See "What you bring" in `README.md`.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
more details.
