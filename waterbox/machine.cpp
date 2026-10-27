// machine.cpp — thin eSpeccy wrapper.
//
// NOTE: "std.h" must come first, like every upstream .cpp: the byte/dword/
// qword types used throughout devices/ are declared by std_types.h via it.
#include "std.h"
#include "machine.h"
#include "speccy.h"
#include "file-types.h"
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
uint8_t* Machine::RamBase() { return (uint8_t*)speccy->Memory()->Get(eMemory::P_RAM0); }



bool Machine::OpenFile(const char* path) {
  return xPlatform::OpenGameFile(speccy, path);
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

void Machine::Reset() {
  speccy->Reset();
  // Upstream A_RESET selects the 128K editor/menu page after reset when not
  // in 48K mode (eRom::Reset leaves the service page mapped). Without this
  // a firmware-only 128K boot strands in the service ROM. Tape/snapshot
  // paths select their own page right after, exactly like upstream.
  if(!speccy->Mode48k())
    speccy->Device<eRom>()->SelectPage(eRom::ROM_128_1);
}

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
// P1 Kempston, P2 Sinclair (=upstream SINCLAIR2 map 6/7/8/9/0), P3 Cursor
// (=upstream CURSOR map 7/6/5/8/0), P4 QAOP (=upstream QAOPM map Q/A/O/P/M),
// console Space/Enter aliases, P5 the full keyboard in upstream eKeyboard
// matrix order.
struct ButtonBinding { bool kbd; char key; };
static const ButtonBinding kButtons[] = {
  {false,'u'}, {false,'d'}, {false,'l'}, {false,'r'}, {false,'f'}, // P1 Kempston U/D/L/R/Fire
  {true,'9'}, {true,'8'}, {true,'6'}, {true,'7'}, {true,'0'},      // P2 Sinclair
  {true,'7'}, {true,'6'}, {true,'5'}, {true,'8'}, {true,'0'},      // P3 Cursor
  {true,'Q'}, {true,'A'}, {true,'O'}, {true,'P'}, {true,'M'},      // P4 QAOP
  {true,' '}, {true,'e'},                                         // console Key.Space, Key.Enter
  {true,'c'}, {true,'Z'}, {true,'X'}, {true,'C'}, {true,'V'},      // P5 keyboard row 7
  {true,'A'}, {true,'S'}, {true,'D'}, {true,'F'}, {true,'G'},      // P5 row 6
  {true,'Q'}, {true,'W'}, {true,'E'}, {true,'R'}, {true,'T'},      // P5 row 5
  {true,'1'}, {true,'2'}, {true,'3'}, {true,'4'}, {true,'5'},      // P5 row 4
  {true,'0'}, {true,'9'}, {true,'8'}, {true,'7'}, {true,'6'},      // P5 row 3
  {true,'P'}, {true,'O'}, {true,'I'}, {true,'U'}, {true,'Y'},      // P5 row 2
  {true,'e'}, {true,'L'}, {true,'K'}, {true,'J'}, {true,'H'},      // P5 row 1
  {true,' '}, {true,'s'}, {true,'M'}, {true,'N'}, {true,'B'},      // P5 row 0
};

void Machine::SetButtonByIndex(int index, bool held) {
  if(index < 0 || index >= ButtonCount())
    return;
  if(held)
    lastMask |= (1ull << index);
  else
    lastMask &= ~(1ull << index);
  ApplyLastMask();
}

void Machine::ApplyMask(uint64_t mask) {
  lastMask = mask;
  ApplyLastMask();
}

void Machine::ApplyLastMask() {
  // Many buttons drive the same upstream key (every preset aliases P5 keys,
  // and Key.Space/Enter alias P5 Space/Enter): the level is the OR over all
  // of them, applied once per distinct key, so the last writer can never
  // release a key another button still holds.
  bool kbd[128] = {}, joy[128] = {};
  for(int i = 0; i < ButtonCount(); i++) {
    if(((lastMask >> i) & 1ull) == 0)
      continue;
    const ButtonBinding& b = kButtons[i];
    (b.kbd ? kbd : joy)[(unsigned char)b.key] = true;
  }
  bool doneK[128] = {}, doneJ[128] = {};
  for(int i = 0; i < ButtonCount(); i++) {
    const ButtonBinding& b = kButtons[i];
    unsigned char k = (unsigned char)b.key;
    if(b.kbd) {
      if(doneK[k])
        continue;
      doneK[k] = true;
      speccy->Device<eKeyboard>()->OnKey(b.key, kbd[k], false, false, false);
    } else {
      if(doneJ[k])
        continue;
      doneJ[k] = true;
      speccy->Device<eKempstonJoy>()->OnKey(b.key, joy[k]);
    }
  }
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
