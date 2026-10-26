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

Machine::Machine() : speccy(new eSpeccy) {}
Machine::~Machine() { delete speccy; }
void Machine::Reset() { speccy->Reset(); }
void Machine::FrameAdvance() { speccy->Update(NULL); }
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



void Machine::SetButton(const char* name, bool held) {
  // Levels, not events: the host says what is held. Called with the FULL
  // state every frame, so press and release are both just the current level.
  struct Map { const char* name; char key; bool kbd; };
  static const Map map[] = {
    {"Kempston.Right", 'r', false}, {"Kempston.Left", 'l', false},
    {"Kempston.Down", 'd', false}, {"Kempston.Up", 'u', false},
    {"Kempston.Fire", 'f', false},
    {"Key.Space", ' ', true}, {"Key.Enter", 'e', true},
    {NULL, 0, false},
  };
  for(const Map* m = map; m->name; m++) {
    if(!strcmp(name, m->name)) {
      if(m->kbd)
        speccy->Device<eKeyboard>()->OnKey(m->key, held, false, false, false);
      else
        speccy->Device<eKempstonJoy>()->OnKey(m->key, held);
      return;
    }
  }
}

void Machine::SetInputMask(uint8_t kempston, uint8_t keys) {
  // Byte 0: Kempston (bit0 Right, bit1 Left, bit2 Down, bit3 Up, bit4 Fire).
  // Byte 1: keyboard (bit0 Space, bit1 Enter). Applies the full level every
  // call — the ONLY input path in both flavors.
  SetButton("Kempston.Right", (kempston & 0x01) != 0);
  SetButton("Kempston.Left",  (kempston & 0x02) != 0);
  SetButton("Kempston.Down",  (kempston & 0x04) != 0);
  SetButton("Kempston.Up",    (kempston & 0x08) != 0);
  SetButton("Kempston.Fire",  (kempston & 0x10) != 0);
  SetButton("Key.Space",      (keys & 0x01) != 0);
  SetButton("Key.Enter",      (keys & 0x02) != 0);
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
