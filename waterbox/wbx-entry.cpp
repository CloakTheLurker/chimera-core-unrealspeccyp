// wbx-entry.cpp — the guest ABI.
//
// The entries the engine probes after Init. Built ONLY for the guest
// (-DWBX_GUEST, musl toolchain); the native harness never compiles this.
// Signatures follow the engine: FrameAdvance takes the packed 64-bit button
// mask (button i -> bit i of waterbox.config input.buttons), SetButton the
// per-button deltas. Both write levels through the same Machine path, so
// whichever the engine uses (or both), the machine sees the same levels.
//
// State: one Machine (Pentagon 128K), owned here. Firmware arrives as files
// the host mounted under their IDs (patch 001: bare "sos128_0.rom" etc.).
// Settings arrive as a mounted "settings" file (miniBox convention); Init
// reads mode48k/fastTape/soundChip and applies them before Reset.
// Video: ULA indexed framebuffer converted with palette.h (same function
// the native parity hash uses). Audio: Machine::MixedAudio, pulled once per
// frame — pulling runs the machine's callbacks, so the guest pulls exactly
// like the reference.
#include "std.h" // upstream types first, like every upstream .cpp
#include "machine.h"
#include "palette.h"
#include <emulibc.h>
#include <waterbox_settings.h>

static Machine* g_machine = 0;
static uint32_t g_bgra[320 * 240]; // == VideoWidth * VideoHeight (a static call is not a constant-expression)
static int16_t g_audio[2048]; // > one frame (882 pairs) with headroom

ECL_EXPORT bool Init(void) {
  g_machine = new Machine();
  int mode48k = wbx_setting_bool("mode48k", 0);
  int fastTape = wbx_setting_bool("fastTape", 1);
  char chip[16] = {0};
  int soundChip = 0; // 0 = ay, 1 = ym
  if(wbx_setting_str("soundChip", chip, sizeof chip) && chip[0] == 'y' && chip[1] == 'm')
    soundChip = 1;
  g_machine->Configure(mode48k != 0, fastTape != 0, soundChip);
  g_machine->Reset();
  return g_machine != 0;
}

// The engine's packed button mask, whole level every frame.
ECL_EXPORT void FrameAdvance(uint64_t buttons) {
  g_machine->ApplyMask(buttons);
  g_machine->FrameAdvance();
}

// Per-button deltas the engine also sends (required past 64 buttons;
// idempotent with FrameAdvance — both write levels through the same path).
ECL_EXPORT void SetButton(int32_t index, int32_t value) {
  if(g_machine)
    g_machine->SetButtonByIndex(index, value != 0);
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
