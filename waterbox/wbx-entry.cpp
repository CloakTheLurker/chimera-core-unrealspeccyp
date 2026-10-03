// wbx-entry.cpp — the guest ABI (M2 stub; signatures only until M2).
//
// Exports the entries the engine probes after Init: Init, FrameAdvance,
// GetVideoBgra, GetAudio, GetVsyncNumerator/Denominator. M0/M1 do not build
// this file for the guest; it exists so the shape of the M2 work is
// reviewable early.
#include <cstdint>

#if defined(_WIN32)
#define ECL_EXPORT __declspec(dllexport)
#else
#define ECL_EXPORT __attribute__((visibility("default")))
#endif

extern "C" {
ECL_EXPORT bool Init(const char* rom, const char* settings_json);
ECL_EXPORT void FrameAdvance(const uint8_t* input_bits, int32_t input_len);
ECL_EXPORT const uint32_t* GetVideoBgra(int32_t* w, int32_t* h);
ECL_EXPORT uint32_t GetAudio(int16_t* stereo_interleaved, uint32_t capacity);
ECL_EXPORT int32_t GetVsyncNumerator(void);
ECL_EXPORT int32_t GetVsyncDenominator(void);
}

bool Init(const char*, const char*) { return false; }
void FrameAdvance(const uint8_t*, int32_t) {}
const uint32_t* GetVideoBgra(int32_t* w, int32_t* h) {
  if (w) *w = 320;
  if (h) *h = 240;
  return nullptr;
}
uint32_t GetAudio(int16_t*, uint32_t) { return 0; }
// Two places keep vsync in step: waterbox.config and these two.
int32_t GetVsyncNumerator(void) { return 50; }
int32_t GetVsyncDenominator(void) { return 1; }
