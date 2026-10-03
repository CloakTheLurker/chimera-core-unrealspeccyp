// machine.cpp — thin eSpeccy wrapper. M0 only; M1 adds the virtual-time seam.
//
// NOTE: "std.h" must come first, like every upstream .cpp: the byte/dword/
// qword types used throughout devices/ are declared by std_types.h via it.
#include "std.h"
#include "machine.h"
#include "speccy.h"
#include "devices/memory.h"
#include "devices/ula.h"
#include "devices/input/keyboard.h"
#include "devices/input/kempston_joy.h"
#include "devices/input/kempston_mouse.h"

Machine::Machine() : speccy(new eSpeccy) {}
Machine::~Machine() { delete speccy; }
void Machine::Reset() { speccy->Reset(); }
void Machine::FrameAdvance() { speccy->Update(NULL); }
uint64_t Machine::TStates() const { return speccy->T(); }
const void* Machine::Video() const { return speccy->Device<eUla>()->Screen(); }

bool Machine::OpenFile(const char* /*path*/, const void* /*data*/, size_t /*size*/) {
  // M0: loads go through eFileType in the harness (run-native.cpp).
  // Kept here so the guest entry can share it at M2 without forking.
  return false;
}

void Machine::PullAudio(int /*source*/, void* /*dst*/, uint32_t* /*inout_samples*/) {
  // M0 stub: the harness reads eDeviceSound directly so native and guest are
  // forced to pull identically (porting doc: pulling runs machine callbacks).
}

void Machine::SetButton(const char* /*name*/, bool /*held*/) {
  // M2: levels, not events — the host says what is held this frame.
}
