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

void Machine::SetButton(const char* /*name*/, bool /*held*/) {
  // M2: levels, not events — the host says what is held this frame.
}
