// machine.h — the emulator, its clock, and the stepping loop (M0 thin wrapper).
//
// Wraps eSpeccy (extern/upstream/speccy.h): construction builds the Pentagon
// machine, Reset() re-inits devices, FrameAdvance() runs exactly one frame
// via eSpeccy::Update(NULL), TStates() exposes the instruction-bought clock
// M1 will seam. Video is the ULA framebuffer (eUla::Screen(), 320x240);
// audio is pulled from the three eDeviceSound sources at frame end.
#pragma once
#include <cstddef>
#include <cstdint>

class eSpeccy;

class Machine {
public:
  Machine();
  ~Machine();
  void Reset();
  void FrameAdvance();        // one 1/50s frame: eSpeccy::Update(NULL)
  uint64_t TStates() const;  // eSpeccy::T(): the virtual-time base
  const void* Video() const; // eUla::Screen(), 320x240 32-bit pixels
  static int VideoWidth() { return 320; }
  static int VideoHeight() { return 240; }
  bool OpenFile(const char* path, const void* data, size_t size);
  void PullAudio(int source, void* dst, uint32_t* inout_samples);
  void SetButton(const char* name, bool held);
private:
  eSpeccy* speccy;
};
