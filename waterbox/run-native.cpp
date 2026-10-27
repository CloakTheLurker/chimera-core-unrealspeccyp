// run-native.cpp — the reference harness (M0 boot + M1 virtual time).
//
// Steps the machine with NO wall clock (--clock virtual, the default):
// every frame is bought with executed instructions (71680 t-states), audio
// is pulled at frame end in both flavors (pulling runs the machine's own
// callbacks — the reference must pull too or native and guest diverge), and
// video is hashed from the ULA framebuffer. Deliberately absent: eTick,
// SDL_Delay-style pacing, VideoPaused backpressure (see usp_time.h).
//
// --clock host replays the SDL platform's wall coupling (pad to wall 20ms,
// drop late machine frames) for the gate's negative control only.
//
// Firmware: the machine needs its ROMs (eRom::Init asserts/exits without
// them). They ship in-tree at extern/upstream/res/rom/; --resdir overrides,
// else resolved from argv[0] (<root>/build/native/run-native ->
// <root>/extern/upstream/) with CWD fallbacks. M2 mounts firmware by name
// in the guest; this native-only path just finds the files.
//
// Reports one machine-parseable line:
//   run-native frames=N stepped=S dropped=D tstates=T vhash=H bhash=H
//     mhash=H ahash=H state=H wall_ms=W vms=V clock=C file=F
// vhash covers the raw indexed framebuffer, bhash the BGRA conversion
// (palette.h — the same function the guest uses), mhash the mixed stereo
// (Machine::MixedAudio — the same function the guest GetAudio uses),
// ahash the three raw source streams (native-only diagnostic). state mixes
// vhash + bhash + mhash + t-states + stepped: the parity leg compares it
// across flavors. vms is the VirtualClock reading (instruction-bought ms).
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "usp_time.h"
#include "machine.h"
#include "palette.h"
#include "platform/io.h"

static uint64_t fnv1a(const void* data, size_t len, uint64_t h) {
  const unsigned char* p = (const unsigned char*)data;
  while(len--) {
    h ^= *p++;
    h *= 1099511628211ULL;
  }
  return h;
}
static uint64_t mix_hash(uint64_t h, uint64_t v) {
  h ^= v + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
  return h;
}

static bool HasRoms(const char* dir) {
  char p[4400];
  snprintf(p, sizeof p, "%sres/rom/sos128_0.rom", dir);
  FILE* f = fopen(p, "rb");
  if(f)
    fclose(f);
  return f != NULL;
}

// Returns the resource dir (with trailing slash) or NULL when no ROMs found.
static const char* FindResDir(const char* argv0, char* buf, size_t len) {
  static char bindir[4096];
  const char* slash = strrchr(argv0, '/');
#ifdef _WIN32
  const char* bslash = strrchr(argv0, '\');
  if(bslash && (!slash || bslash > slash))
    slash = bslash;
#endif
  if(slash) {
    size_t n = (size_t)(slash - argv0);
    if(n >= sizeof bindir)
      n = sizeof bindir - 1;
    memcpy(bindir, argv0, n);
    bindir[n] = 0;
  } else {
    strcpy(bindir, ".");
  }
  snprintf(buf, len, "%s/../../extern/upstream/", bindir);
  if(HasRoms(buf))
    return buf;
  if(HasRoms("extern/upstream/")) {
    strcpy(buf, "extern/upstream/");
    return buf;
  }
  if(HasRoms("./")) {
    strcpy(buf, "./");
    return buf;
  }
  return NULL;
}

int main(int argc, char** argv) {
  const char* file = NULL;
  const char* resdir_override = NULL;
  int frames = 600;
  const char* clock = "virtual";
  int stall_ms = 0;
  int stall_at = -1;
  bool trace = false;
  // Input levels as the engine's 64-bit button mask (bit i = input.buttons[i]
  // in waterbox.config order): --input-mask 0x1F kempston bits held for
  // frames [input-from, input-to); --input-keys bit0 Space -> bit 20,
  // bit1 Enter -> bit 21. Applied via the same Machine::ApplyMask the guest
  // uses — parity compares the identical path.
  uint64_t input_mask = 0; unsigned input_keys = 0; // mask is full 64-bit: the P5 keyboard lives past bit 21
  int input_from = -1, input_to = -1;
  bool mode48k = false, fastTape = true;
  const char* soundChip = "ay";
  for(int i = 1; i < argc; i++) {
    if(!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
    else if(!strcmp(argv[i], "--clock") && i + 1 < argc) clock = argv[++i];
    else if(!strcmp(argv[i], "--stall-ms") && i + 1 < argc) stall_ms = atoi(argv[++i]);
    else if(!strcmp(argv[i], "--trace-instr")) trace = true;
    else if(!strcmp(argv[i], "--stall-at") && i + 1 < argc) stall_at = atoi(argv[++i]);
    else if(!strcmp(argv[i], "--resdir") && i + 1 < argc) resdir_override = argv[++i];
    else if(!strcmp(argv[i], "--input-mask") && i + 1 < argc) input_mask = strtoull(argv[++i], NULL, 0);
    else if(!strcmp(argv[i], "--input-keys") && i + 1 < argc) input_keys = (unsigned)strtoul(argv[++i], NULL, 0);
    else if(!strcmp(argv[i], "--input-from") && i + 1 < argc) input_from = atoi(argv[++i]);
    else if(!strcmp(argv[i], "--input-to") && i + 1 < argc) input_to = atoi(argv[++i]);
    else if(!strcmp(argv[i], "--mode48k")) mode48k = true;
    else if(!strcmp(argv[i], "--no-fast-tape")) fastTape = false;
    else if(!strcmp(argv[i], "--sound-chip") && i + 1 < argc) soundChip = argv[++i];
    else if(!strcmp(argv[i], "--dump-video")) {} // kept: video is always hashed (M1)
    else if(!strcmp(argv[i], "--pull-audio")) {} // kept: audio is always pulled (M1)
    else if(!strcmp(argv[i], "--help")) {
      printf("usage: run-native [--frames N] [--clock virtual|host] [--stall-ms M --stall-at F] [--resdir D] [--trace-instr] [--input-mask M --input-from F --input-to T] [file]"); puts("");
      printf("  no file: firmware boot (Reset + step); file: eFileType-open then step.\n");
      return 0;
    } else file = argv[i];
  }
  bool host = !strcmp(clock, "host");
  if(strcmp(clock, "virtual") && !host) {
    printf("run-native: unknown --clock %s (want virtual|host)\n", clock);
    return 1;
  }
  if(stall_at < 0)
    stall_at = frames / 2;

  if(resdir_override) {
    xIo::SetResourcePath(resdir_override);
  } else {
    static char resbuf[4096];
    const char* found = FindResDir(argv[0], resbuf, sizeof resbuf);
    if(!found) {
      printf("run-native: firmware ROMs not found (tried <bindir>/../../extern/upstream/, extern/upstream/, ./); use --resdir\n");
      return 1;
    }
    xIo::SetResourcePath(found);
  }

  Machine m;
  int chip = (soundChip[0] == 'y' && soundChip[1] == 'm') ? 1 : 0;
  m.Configure(mode48k, fastTape, chip);
  m.Reset();
  if(file) {
    if(!m.OpenFile(file)) {
      printf("run-native: cannot open %s (unsupported format)\n", file);
      return 1;
    }
  }

  const uint64_t FNV_SEED = 1469598103934665603ULL;
  uint64_t vhash = FNV_SEED, bhash = FNV_SEED;
  uint64_t mhash = FNV_SEED, ahash = FNV_SEED;
  static uint32_t bgra[320 * 240];
  static int16_t mixed[2048];
  VirtualClock vclock(0, m.FrameTacts(), 50);
  FramePacer pacer(20);
  if(host)
    pacer.Start();
  uint64_t t0 = usp_host_ms();
  int stepped = 0;
  for(int f = 0; f < frames; f++) {
    if(stall_ms && f == stall_at)
      usp_sleep_ms((unsigned)stall_ms); // host stalls; the machine must not notice
    if(host && !pacer.Next())
      continue; // DROP: wall-coupled catch-up skipped this machine frame
    bool held = (input_from >= 0 && f >= input_from && (input_to < 0 || f < input_to));
    // Config-order mask bits: 0-4 kempston, 20 Space, 21 Enter.
    uint64_t buttons = 0;
    if(held) {
      buttons |= input_mask; // the whole declared set, P1 through P5
      if(input_keys & 0x01) buttons |= (1ull << 20);
      if(input_keys & 0x02) buttons |= (1ull << 21);
    }
    m.ApplyMask(buttons);
    m.FrameAdvance();
    ++stepped;
    vclock.AdvanceFrames();
    const uint8_t* raw = (const uint8_t*)m.Video();
    vhash = fnv1a(raw, (size_t)Machine::VideoBytes(), vhash);
    usp_framebuffer_to_bgra(raw, bgra, Machine::VideoBytes());
    bhash = fnv1a(bgra, sizeof bgra, bhash);
    for(int s = 0; s < m.AudioSources(); s++) {
      uint32_t r = m.AudioDataReady(s);
      if(r)
        ahash = fnv1a(m.AudioData(s), r, ahash);
    }
    uint32_t wrote = m.MixedAudio(mixed, 2048); // drains the sources
    if(wrote)
      mhash = fnv1a(mixed, wrote * sizeof(int16_t), mhash);
    if(host)
      pacer.Stepped();
    if(trace && (f % 100 == 0))
      printf("trace: frame=%d tstates=%llu\n", f, (unsigned long long)m.TStates());
  }
  uint64_t wall = usp_host_ms() - t0;
  uint64_t state = vhash;
  state = mix_hash(state, bhash);
  state = mix_hash(state, mhash);
  state = mix_hash(state, m.TStates());
  state = mix_hash(state, (uint64_t)stepped);
  printf("run-native frames=%d stepped=%d dropped=%u tstates=%llu vhash=%016llx bhash=%016llx mhash=%016llx ahash=%016llx state=%016llx wall_ms=%llu vms=%llu clock=%s file=%s\n",
      frames, stepped, host ? pacer.dropped() : 0,
      (unsigned long long)m.TStates(),
      (unsigned long long)vhash, (unsigned long long)bhash,
      (unsigned long long)mhash, (unsigned long long)ahash,
      (unsigned long long)state,
      (unsigned long long)wall, (unsigned long long)vclock.NowMs(),
      clock, file ? file : "(firmware)");
  return 0;
}
