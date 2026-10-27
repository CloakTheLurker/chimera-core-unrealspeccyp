// machine.h — the emulator, its clock, and the stepping loop.
//
// Wraps eSpeccy (extern/upstream/speccy.h): construction builds the Pentagon
// machine, Reset() re-inits devices, FrameAdvance() runs exactly one frame
// via eSpeccy::Update(NULL), TStates() exposes the instruction-bought clock
// (M1 seam: VirtualClock in usp_time.h derives wall-independent time from it).
// Video is the ULA framebuffer (eUla::Screen(), 320x240 INDEXED bytes —
// palette.h converts to BGRA identically in both flavors); audio is pulled
// from the three eDeviceSound sources at frame end, in both flavors.
//
// Input is levels, not events. The engine packs the declared buttons into a
// 64-bit mask (button i -> bit i of waterbox.config input.buttons order) and
// the guest's FrameAdvance(uint64_t) applies the whole level every frame;
// the optional SetButton export applies single-button deltas the same way.
// Both flavors share Machine::ApplyMask, so native-vs-guest parity compares
// the identical input path. Bit order is the movie contract: NEVER reorder.
#pragma once
#include <cstddef>
#include <cstdint>

class eSpeccy;

class Machine {
public:
  Machine();
  ~Machine();
  // Reads the mounted settings file (miniBox "settings" channel) and applies
  // mode48k / fastTape / soundChip. Native harness passes its own values.
  void Configure(bool mode48k, bool fastTape, int soundChip);
  void Reset();
  void FrameAdvance();        // one 1/50s frame: eSpeccy::Update(NULL)
  uint64_t TStates() const;  // eSpeccy::T(): the virtual-time base
  uint32_t FrameTacts() const; // t-states per frame (71680 Pentagon)
  const void* Video() const; // eUla::Screen(), 320x240 indexed bytes
  static int VideoWidth() { return 320; }
  static int VideoHeight() { return 240; }
  static int VideoBytes() { return 320 * 240; }
  bool OpenFile(const char* path, const void* data, size_t size);
  int AudioSources();                    // 3: beeper, AY, tape
  const void* AudioData(int source);
  uint32_t AudioDataReady(int source);   // bytes
  void AudioDataUse(int source, uint32_t size);
  // Mixes all sources to int16 stereo (same function the guest GetAudio
  // uses; the native parity hash covers it too). Drains the sources.
  // Returns int16 elements written (<= capacity).
  uint32_t MixedAudio(int16_t* stereo, uint32_t capacity);
  // The engine's button mask (bit i = input.buttons[i]), full level applied
  // every frame. Also the native harness path (it builds the same mask).
  void ApplyMask(uint64_t mask);
  // One button by config index (the SetButton export's delta path).
  void SetButtonByIndex(int index, bool held);
  // Number of declared buttons (bit count of the mask).
  static int ButtonCount() { return 22; }
private:
  eSpeccy* speccy;
  bool fast_tape;
};
