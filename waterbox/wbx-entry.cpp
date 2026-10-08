// wbx-entry.cpp — the guest ABI: Init, FrameAdvance, GetVideoBgra...
//
// The entries the engine probes after Init. Built ONLY for the guest
// (-DWBX_GUEST, musl toolchain); the native harness never compiles this.
//
// State: one Machine (Pentagon 128K), owned here. Firmware arrives as files
// the host mounted under their IDs (patch 001: bare "sos128_0.rom" etc.);
// Init -> Reset() loads them via eRom::Init during devices.Init().
// Settings arrive as a mounted "settings" file (miniBox convention); M2
// ignores the content (defaults), the reader lands with SuggestSettings.
// Video: ULA indexed framebuffer converted with palette.h (same function
// the native parity hash uses). Audio: Machine::MixedAudio, pulled once per
// frame — pulling runs the machine's callbacks, so the guest pulls exactly
// like the reference. Input: M2 ignores levels (parity is on firmware boot;
// SetButton lands with the input work) — the signature is already the one
// the engine will drive.
#include "std.h" // upstream types first, like every upstream .cpp
#include "machine.h"
#include "palette.h"
#include <emulibc.h>

static Machine* g_machine = 0;
static uint32_t g_bgra[Machine::VideoWidth() * Machine::VideoHeight()];
static int16_t g_audio[2048]; // > one frame (882 pairs) with headroom

ECL_EXPORT bool Init(void) {
  g_machine = new Machine();
  g_machine->Reset();
  return g_machine != 0;
}

ECL_EXPORT void FrameAdvance(const uint8_t* input_bits, int32_t input_len) {
  (void)input_bits;
  (void)input_len; // M2: levels, not events — applied with the input work
  g_machine->FrameAdvance();
}

ECL_EXPORT const uint32_t* GetVideoBgra(int32_t* w, int32_t* h) {
  if(w) *w = Machine::VideoWidth();
  if(h) *h = Machine::VideoHeight();
  usp_framebuffer_to_bgra((const uint8_t*)g_machine->Video(), g_bgra,
      Machine::VideoWidth() * Machine::VideoHeight());
  return g_bgra;
}

// The raw indexed framebuffer (76800 bytes): the driver/parity leg compares
// the machine, not just the converted picture.
ECL_EXPORT const uint8_t* GetVideoRaw(void) {
  return (const uint8_t*)g_machine->Video();
}

ECL_EXPORT uint32_t GetAudio(int16_t* stereo_interleaved, uint32_t capacity) {
  if(!stereo_interleaved || !capacity)
    return 0;
  uint32_t n = capacity > 2048 ? 2048 : capacity;
  uint32_t wrote = g_machine->MixedAudio(g_audio, n);
  for(uint32_t i = 0; i < wrote; i++)
    stereo_interleaved[i] = g_audio[i];
  return wrote;
}

// The last mix, for drivers that read rather than pass a buffer.
ECL_EXPORT const int16_t* GetAudioBuf(void) {
  return g_audio;
}

ECL_EXPORT uint64_t GetTStates(void) {
  return g_machine->TStates();
}

// Two places keep vsync in step: waterbox.config and these two.
ECL_EXPORT int32_t GetVsyncNumerator(void) { return 50; }
ECL_EXPORT int32_t GetVsyncDenominator(void) { return 1; }
