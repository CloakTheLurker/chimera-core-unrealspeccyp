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
  // Both halves of what upstream's SetupSoundChip does: SetChip alone only
  // changes how register numbers are masked, so AY and YM produced identical
  // audio for any legal program. The volume table is the audible difference.
  eAY* ay = speccy->Device<eAY>();
  ay->SetChip(soundChip == 1 ? eAY::CHIP_YM : eAY::CHIP_AY);
  ay->SetVolumes(0x7FFF,
                 soundChip == 1 ? SNDR_VOL_YM : SNDR_VOL_AY,
                 SNDR_PAN_ABC);
}

void Machine::Reset() {
  speccy->Reset();
  // Upstream A_RESET selects the 128K editor/menu page after reset when not
  // in 48K mode (eRom::Reset leaves the service page mapped). Without this
  // a firmware-only 128K boot strands in the service ROM. Tape/snapshot
  // paths select their own page right after, exactly like upstream.
  // (Tape autostart lives in FileTypeTape::Open, after its Reset: Reset
  // rewinds and stops the tape, so starting must come after, not here.)
  if(!speccy->Mode48k())
    speccy->Device<eRom>()->SelectPage(eRom::ROM_128_1);
}

// Set whenever Enter is held in the current level; FrameAdvance uses it to
// start an armed tape (the Enter that submits LOAD "" or picks Tape Loader).
static bool g_enter_pressed = false;

void Machine::FrameAdvance() {
  // A tape opened while the 128K menu is up is armed, not started: the menu
  // polls EAR, so a tape already playing would be consumed before the user
  // picks Tape Loader (the loader then starts mid-tape). Start it when Enter
  // is pressed - the key that selects Tape Loader and the key that submits
  // LOAD "" - which is the moment a real user presses Play. The tape only
  // advances on EAR reads, so a 48K or 128 BASIC LOAD starts from position 0
  // even though the key was pressed slightly earlier.
  if(xPlatform::TapeStartPending() && g_enter_pressed) {
    speccy->Device<eTape>()->Start();
    xPlatform::TapeStartConsumed();
  }
  g_enter_pressed = false;
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
  // release a key another button still holds. The Caps/Symbol Shift states
  // ride every call (upstream OnKey clears both shifts unless told
  // otherwise, so a hardcoded false here would make the P5 shift keys
  // unholdable and break quoted strings and shifted capitals outright).
  bool kbd[128] = {}, joy[128] = {};
  for(int i = 0; i < ButtonCount(); i++) {
    if(((lastMask >> i) & 1ull) == 0)
      continue;
    const ButtonBinding& b = kButtons[i];
    (b.kbd ? kbd : joy)[(unsigned char)b.key] = true;
  }
  if(kbd[(unsigned char)'e'])
    g_enter_pressed = true;
  bool doneK[128] = {}, doneJ[128] = {};
  for(int i = 0; i < ButtonCount(); i++) {
    const ButtonBinding& b = kButtons[i];
    unsigned char k = (unsigned char)b.key;
    if(b.kbd) {
      if(doneK[k])
        continue;
      doneK[k] = true;
      speccy->Device<eKeyboard>()->OnKey(b.key, kbd[k], kbd['c'], false, kbd['s']);
    } else {
      if(doneJ[k])
        continue;
      doneJ[k] = true;
      speccy->Device<eKempstonJoy>()->OnKey(b.key, joy[k]);
    }
  }
}

// MixedAudio: sum the machine's two audible sources (beeper and AY) and
// write int16 stereo pairs. An eDeviceSound sample is ONE int32 with the
// left channel in the low word and the right in the high word
// (device_sound.h, SNDSAMPLE): it must be unpacked, not treated as a mono
// value. Clamping the packed int32 saturated every nonzero sample to
// +32767, which is the buzz heard while a tape played and over AY music.
// The tape device (source 2) is a data signal, not machine audio (upstream
// offers it as a separate "sound" choice, default AY); mix beeper + AY and
// drain the tape so its ring buffer never overruns. min-ready over the two
// mixed sources, then drain all three — identical in native and guest, so
// the parity leg compares one mix.
uint32_t Machine::MixedAudio(int16_t* stereo, uint32_t capacity) {
  uint32_t ready0 = AudioDataReady(0) / 4;
  uint32_t ready1 = AudioDataReady(1) / 4;
  uint32_t n = ready0 < ready1 ? ready0 : ready1;
  if(n * 2 > capacity) n = capacity / 2;
  const int32_t* s0 = (const int32_t*)AudioData(0);
  const int32_t* s1 = (const int32_t*)AudioData(1);
  for(uint32_t i = 0; i < n; i++) {
    int32_t l = (int16_t)(s0[i] & 0xFFFF) + (int16_t)(s1[i] & 0xFFFF);
    int32_t r = (int16_t)(s0[i] >> 16) + (int16_t)(s1[i] >> 16);
    if(l > 32767) l = 32767; else if(l < -32768) l = -32768;
    if(r > 32767) r = 32767; else if(r < -32768) r = -32768;
    stereo[i * 2] = (int16_t)l;
    stereo[i * 2 + 1] = (int16_t)r;
  }
  AudioDataUse(0, AudioDataReady(0));
  AudioDataUse(1, AudioDataReady(1));
  AudioDataUse(2, AudioDataReady(2)); // tape: drained, never mixed
  return n * 2;
}
