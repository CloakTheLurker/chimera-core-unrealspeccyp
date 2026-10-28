#pragma once
// Adapter-owned game file types (M5).
//
// The upstream format handlers (tape images, snapshots) live in
// speccy_handler.cpp — the UI handler, which this core deliberately does
// NOT build (headless native, no frontend). The eFileType registrations the
// harness and guest need therefore live here, calling the same upstream
// entry points the handler's versions call (eTape::Open, xSnapshot::Load),
// minus the UI parts (macros, tape autostart).
//
// Registration happens via static objects at startup, like upstream's.

class eSpeccy;

namespace xPlatform
{

// Open the game file at path (native: host path; guest: mounted name),
// parsing the whole file and loading it into the machine. Returns false
// when the extension names no registered type or the parse fails.
bool OpenGameFile(eSpeccy* speccy, const char* path);

// A tape opened while the 128K menu is up must not play yet: the menu ROM
// polls EAR during boot, and a playing tape would be consumed before the
// user picks Tape Loader (the loader then starts mid-tape). Keep it armed
// and start it when Enter is pressed - the key that selects Tape Loader and
// the key that submits LOAD "" - which is when a real user presses Play.
// Machine::FrameAdvance consumes the flag.
bool TapeStartPending();
void TapeStartConsumed();

}
//namespace xPlatform
