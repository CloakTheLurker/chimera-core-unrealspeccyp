// palette.h — the core's indexed framebuffer -> 32-bit BGRA (shared).
//
// eUla::Screen() yields bytes holding 4-bit (paper<<4|ink) values through
// colortab1/2 (devices/ula.cpp: zx-attr -> pc-attr, flash alternates per
// frame). The GLES renderer maps those through a 16-entry BGR565 cache
// (platform/gles2/gles2.cpp eCachedColors: base brightness 200, bright 255
// per channel bit BGR). This is the same math in 8-bit BGRA, used by the
// guest GetVideoBgra AND the native harness parity hash, so both flavors
// compare the same picture.
#pragma once
#include <stdint.h>

static inline uint32_t usp_indexed_to_bgra(uint8_t c) {
  uint8_t i = (c & 8) ? 255 : 200;
  uint8_t b = (c & 1) ? i : 0;
  uint8_t r = (c & 2) ? i : 0;
  uint8_t g = (c & 4) ? i : 0;
  return ((uint32_t)0xFF << 24) | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

static inline void usp_framebuffer_to_bgra(const uint8_t* indexed, uint32_t* bgra, int pixels) {
  for(int n = 0; n < pixels; n++)
    bgra[n] = usp_indexed_to_bgra(indexed[n]);
}
