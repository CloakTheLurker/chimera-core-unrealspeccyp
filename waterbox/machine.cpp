// machine.cpp — thin eSpeccy wrapper.
//
// NOTE: "std.h" must come first, like every upstream .cpp: the byte/dword/
// qword types used throughout devices/ are declared by std_types.h via it.
#include "std.h"
#include "machine.h"
#include "speccy.h"
#include "file_type.h"
#include "devices/memory.h"
#include "devices/ula.h"
#include "devices/input/keyboard.h"
#include "devices/input/kempston_joy.h"
#include "devices/input/kempston_mouse.h"
#include "devices/sound/beeper.h"
#include "devices/sound/ay.h"
#include "devices/input/tape.h"
#include "z80/z80.h"

uint64_t Machine::TStates() const { return speccy->T(); }
uint32_t Machine::FrameTacts() const { return speccy->CPU()->FrameTacts(); }
const void* Machine::Video() const { return speccy->Device<eUla>()->Screen(); }

bool Machine::OpenFile(const char* path, const void* data, size_t size) {
  const xPlatform::eFileType* t = xPlatform::eFileType::FindByName(path);
  if(!t || !t->AbleOpen())
    return false;
  if(data && size)
    return t->Open(data, size);
  return t->Open(path);
}

static eDeviceSound* SoundDev(eSpeccy* speccy, int s) {
  if(s == 0) return speccy->Device<eBeeper>();
  if(s == 1) return speccy->Device<eAY>();
  return speccy->Device<eTape>();
}
int Machine::AudioSources() { return 3; }
const void* Machine::AudioData(int source) { return SoundDev(speccy, source)->AudioData(); }
uint32_t Machine::AudioDataReady(int source) { return SoundDev(speccy, source)->AudioDataReady(); }
void Machine::AudioDataUse(int source, uint32_t size) { SoundDev(speccy, source)->AudioDataUse(size); }


Machine::Machine() : speccy(new eSpeccy), fast_tape(true) {}
Machine::~Machine() { delete speccy; }

void Machine::Configure(bool mode48k, bool fastTape, int soundChip) {
  speccy->Mode48k(mode48k);
  fast_tape = fastTape;
  speccy->Device<eAY>()->SetChip(
      soundChip == 1 ? eAY::CHIP_YM : eAY::CHIP_AY);
}

void Machine::Reset() { speccy->Reset(); }

void Machine::FrameAdvance() {
  // Upstream installs the fast-tape step only while a tape runs (and takes
  // it off when the tape stops); mirror that exactly. The step's ROM-pattern
  // fast paths (incl. delay-loop acceleration) must never fire outside a
  // tape load, and with no tape loaded this is a no-op identical to M2.
  speccy->CPU()->HandlerStep(
      (fast_tape && speccy->Device<eTape>()->Started()) ? fast_tape_emul : NULL);
  speccy->Update(NULL);
}

// Button table in waterbox.config input.buttons declaration order: bit i of
// the engine's 64-bit mask. NEVER reorder (movie contract); append only, and
// past 64 the SetButton export (below) is what carries the rest.
struct ButtonBinding { bool kbd; char key; };
static const ButtonBinding kButtons[] = {
  {false,'u'}, {false,'d'}, {false,'l'}, {false,'r'}, {false,'f'}, // Kempston U/D/L/R/Fire
  {true,'9'}, {true,'8'}, {true,'6'}, {true,'7'}, {true,'0'},      // Sinclair (upstream SINCLAIR2 map)
  {true,'7'}, {true,'6'}, {true,'5'}, {true,'8'}, {true,'0'},      // Cursor (upstream CURSOR map)
  {true,'Q'}, {true,'A'}, {true,'O'}, {true,'P'}, {true,'M'},      // QAOP (upstream QAOPM map)
  {true,' '}, {true,'e'},                                          // Key.Space, Key.Enter
};

void Machine::SetButtonByIndex(int index, bool held) {
  if(index < 0 || index >= ButtonCount())
    return;
  const ButtonBinding& b = kButtons[index];
  if(b.kbd)
    speccy->Device<eKeyboard>()->OnKey(b.key, held, false, false, false);
  else
    speccy->Device<eKempstonJoy>()->OnKey(b.key, held);
}

void Machine::ApplyMask(uint64_t mask) {
  for(int i = 0; i < ButtonCount(); i++)
    SetButtonByIndex(i, ((mask >> i) & 1ull) != 0);
}

// MixedAudio: sum the three sources per sample like eSoundMixer::Update
// (tools/sound_mixer.cpp: int sums of the three int32 streams), clamped to
// int16 stereo pairs. min-ready across sources, then drain all — identical
// in native and guest, so the parity leg compares one mix.
uint32_t Machine::MixedAudio(int16_t* stereo, uint32_t capacity) {
  uint32_t ready0 = AudioDataReady(0) / 4;
  uint32_t ready1 = AudioDataReady(1) / 4;
  uint32_t ready2 = AudioDataReady(2) / 4;
  uint32_t n = ready0;
  if(ready1 < n) n = ready1;
  if(ready2 < n) n = ready2;
  if(n * 2 > capacity) n = capacity / 2;
  const int32_t* s0 = (const int32_t*)AudioData(0);
  const int32_t* s1 = (const int32_t*)AudioData(1);
  const int32_t* s2 = (const int32_t*)AudioData(2);
  for(uint32_t i = 0; i < n; i++) {
    int32_t v = s0[i] + s1[i] + s2[i];
    if(v > 32767) v = 32767;
    if(v < -32768) v = -32768;
    stereo[i * 2] = (int16_t)v;      // mono machine: same on both channels
    stereo[i * 2 + 1] = (int16_t)v;
  }
  AudioDataUse(0, AudioDataReady(0));
  AudioDataUse(1, AudioDataReady(1));
  AudioDataUse(2, AudioDataReady(2));
  return n * 2;
}
