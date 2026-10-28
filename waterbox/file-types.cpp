// file-types.cpp — adapter-owned game file type registrations.
//
// Upstream registers one eFileType per game format inside speccy_handler.cpp
// (the UI handler: macros, tape autostart, disk dialogs). This core never
// builds that file, so the registrations the reference harness and the guest
// need live here instead, calling the same upstream entry points.
//
// Supported (mirrors waterbox.config file_slots formats): tap/tzx/csw tape
// images via eTape::Open; sna/z80/szx snapshots via xSnapshot::Load (with a
// reset first, exactly like the handler does). Zip archives ride the already
// compiled eFileTypeZIP, which delegates each member to a registered type.
// Disk images (trd/scl/...) and replays (rzx) are NOT registered: the slots
// do not offer them, so naming them would be a lie the wizard would act on.
#include "std.h"
#include "file_type.h"
#include "speccy.h"
#include "devices/memory.h"
#include "devices/input/tape.h"
#include "devices/fdd/wd1793.h"
#include "snapshot/snapshot.h"
#include "z80/z80.h"

namespace xPlatform
{

// The machine file types open against. Set by Machine::UseForFiles; the
// reference harness and the guest both go through Machine, so both flavors
// parse the identical bytes the identical way.
static eSpeccy* g_files_machine = 0;
void UseMachineForFiles(eSpeccy* speccy) { g_files_machine = speccy; }
static eSpeccy* FilesMachine() { return g_files_machine; }

static struct eFileTypeTape : public eFileType
{
  virtual bool Open(const void* data, size_t data_size) const
  {
    if(!FilesMachine())
      return false;
    bool ok = FilesMachine()->Device<eTape>()->Open(Type(), data, data_size);
    if(ok)
    {
      // No UI play button and no tape macro exists headless: an opened tape
      // auto-plays (upstream's autoplay path starts it as part of loading).
      // Start AFTER Reset: Reset rewinds and stops the tape, so starting
      // before it would be immediately undone. A finished tape stays
      // finished until re-open (like a real deck at end of tape); without
      // this the tape never moves and LOAD "" hears silence.
      FilesMachine()->Reset();
      // eSpeccy::Reset is the raw device reset: it leaves the service ROM
      // mapped (eRom::Reset). Machine::Reset normally follows it with the
      // 128K menu page, but this file-type layer holds an eSpeccy, so do the
      // same thing here. The 48K machine needs nothing: eRom::Reset already
      // picked sos48 there.
      //
      // Do NOT select ROM_SOS(): in 128K mode that is the 128K's 48 BASIC
      // ROM, so opening a tape replaced the menu the moment a tape arrived -
      // the machine stayed a 128K, but it looked like a 48K and the menu's
      // Tape Loader was gone. A real 128K starts at its menu and switches to
      // 48 BASIC only when the user picks Tape Loader.
      if(!FilesMachine()->Mode48k())
        FilesMachine()->Devices().Get<eRom>()->SelectPage(eRom::ROM_128_1);
      FilesMachine()->Device<eTape>()->Start();
    }
    return ok;
  }
  virtual const char* Type() const { return "tap"; }
} ft_tap;
static struct eFileTypeCSW : public eFileTypeTape
{
  virtual const char* Type() const { return "csw"; }
} ft_csw;
static struct eFileTypeTZX : public eFileTypeTape
{
  virtual const char* Type() const { return "tzx"; }
} ft_tzx;

static struct eFileTypeSnapshot : public eFileType
{
  virtual bool Open(const void* data, size_t data_size) const
  {
    if(!FilesMachine())
      return false;
    FilesMachine()->Reset();
    return xSnapshot::Load(FilesMachine(), Type(), data, data_size);
  }
  virtual const char* Type() const { return "sna"; }
} ft_sna;
static struct eFileTypeZ80 : public eFileTypeSnapshot
{
  virtual const char* Type() const { return "z80"; }
} ft_z80;
static struct eFileTypeSZX : public eFileTypeSnapshot
{
  virtual const char* Type() const { return "szx"; }
} ft_szx;

}
//namespace xPlatform

namespace xPlatform
{

// Open the game file at path (native: host path; guest: mounted name),
// parsing the whole file and loading it into the machine. Zip archives
// delegate each member to a registered type above. Returns false when the
// extension names no registered type or the parse fails.
bool OpenGameFile(eSpeccy* speccy, const char* path)
{
  if(!speccy || !path || !*path)
    return false;
  UseMachineForFiles(speccy);
  const eFileType* t = eFileType::FindByName(path);
  if(!t || !t->AbleOpen()) return false;
  FILE* f = fopen(path, "rb");
  if(!f) return false;
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);
  if(size <= 0 || size > (16 << 20))
  {
    fclose(f);
    return false;
  }
  byte* buf = new byte[(size_t)size];
  size_t r = fread(buf, 1, (size_t)size, f);
  fclose(f);
  bool ok = (r == (size_t)size) && t->Open(buf, (size_t)size);
  delete[] buf;
  return ok;
}

}
//namespace xPlatform
