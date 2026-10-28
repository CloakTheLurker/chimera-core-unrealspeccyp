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
static uint32_t g_audioCount = 0; // stereo pairs in g_audio after the frame

// Lag frames: set when the emulated program reads the keyboard or Kempston
// joystick during a frame (patched IoRead hooks in devices/input); cleared
// at the start of every frame. The engine counts a frame with no reads as
// lag. Native builds never compile this file, so no flavor split is needed.
int g_wbx_inputWasRead = 0;

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
  // The engine mounts the game at waterbox.config romFile ("rom") with the
  // real name under "rom.name" (session without a project uses the alias
  // "/basename"); a project mounts slot files under their own names. Read
  // rom.name when it exists and open that; without it, boot firmware-only.
  char romname[512] = {0};
  FILE* rf = fopen("rom.name", "rb");
  if(rf) {
    size_t n = fread(romname, 1, sizeof romname - 1, rf);
    fclose(rf);
    romname[n] = 0;
    // A project mounts each slot file under its own name, so the bare name
    // opens directly. A directly-opened rom is mounted at romFile ("rom")
    // plus a "/basename" alias; rom.name carries one of those two spellings.
    // Try all three: bare, /bare, then romFile.
    char slashed[520];
    slashed[0] = 0;
    if(romname[0] != '/' && (strlen(romname) + 2 <= sizeof slashed))
    {
      slashed[0] = '/';
      strcpy(slashed + 1, romname);
    }
    if(!g_machine->OpenFile(romname)
        && !(slashed[0] && g_machine->OpenFile(slashed))
        && !g_machine->OpenFile("rom"))
      return false;
  }
  return g_machine != 0;
}

// The engine's packed button mask, whole level every frame.
ECL_EXPORT void FrameAdvance(uint64_t buttons) {
  g_wbx_inputWasRead = 0;
  g_machine->ApplyMask(buttons);
  g_machine->FrameAdvance();
  // The engine reads audio as a pointer (GetAudio, no arguments) after the
  // frame; the mix happens here so both flavors drain the sources at the
  // same point (native run-native mixes right after its FrameAdvance too).
  uint32_t wrote = g_machine->MixedAudio(g_audio, 2048);
  g_audioCount = wrote / 2; // stereo pairs
}

// Per-button deltas the engine also sends (required past 64 buttons;
// idempotent with FrameAdvance — both write levels through the same path).
ECL_EXPORT void SetButton(int32_t index, int32_t value) {
  if(g_machine)
    g_machine->SetButtonByIndex(index, value != 0);
}

ECL_EXPORT const uint32_t* GetVideoBgra(void) {
  usp_framebuffer_to_bgra((const uint8_t*)g_machine->Video(), g_bgra,
      Machine::VideoWidth() * Machine::VideoHeight());
  return g_bgra;
}

// The live size (same as the package declares; here so a reader never trusts
// the declaration over the machine).
ECL_EXPORT int32_t GetVideoWidth(void) { return Machine::VideoWidth(); }
ECL_EXPORT int32_t GetVideoHeight(void) { return Machine::VideoHeight(); }

// The raw indexed framebuffer (76800 bytes): the driver/parity leg compares
// the machine, not just the converted picture.
ECL_EXPORT const uint8_t* GetVideoRaw(void) {
  return (const uint8_t*)g_machine->Video();
}

// Self-described memory domains (guest ABI v1), queried after Init — sizes
// may depend on settings, so there is no package-side table. Domain 0 is the
// machine RAM (writable; 8 consecutive 16K pages), domain 1 the ULA
// framebuffer (read-only: the machine redraws it every frame).
ECL_EXPORT int32_t GetMemoryDomainCount(void) { return 2; }
ECL_EXPORT const char* GetMemoryDomainName(int32_t i) {
  if(i == 0) return "RAM";
  if(i == 1) return "VRAM";
  return 0;
}
ECL_EXPORT uint8_t* GetMemoryDomainPtr(int32_t i) {
  if(!g_machine) return 0;
  if(i == 0) return g_machine->RamBase();
  if(i == 1) return (uint8_t*)g_machine->Video();
  return 0;
}
ECL_EXPORT int64_t GetMemoryDomainSize(int32_t i) {
  if(i == 0) return Machine::RamBytes();
  if(i == 1) return Machine::VideoBytes();
  return 0;
}
ECL_EXPORT int32_t GetMemoryDomainWritable(int32_t i) { return i == 0 ? 1 : 0; }

// The frame's mixed audio (see FrameAdvance): the engine reads the pointer
// (no arguments, like the video) and up to samplesPerFrame pairs from it.
ECL_EXPORT const int16_t* GetAudio(void) {
  return g_audio;
}

// How many stereo pairs GetAudio holds. The engine caps at samplesPerFrame
// itself; the count here is the true one so the parity driver hashes exactly
// what the native harness hashes (a snapshot load flushes ~882 extra samples
// into frame 0, and truncating that would break parity, not keep it).
ECL_EXPORT int32_t GetAudioSampleCount(void) {
  return (int32_t)g_audioCount;
}

// Whether the emulated program read the keyboard or Kempston joystick
// during the frame just stepped (the engine's lag counter reads this).
ECL_EXPORT int32_t InputWasRead(void) {
  return g_wbx_inputWasRead;
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
