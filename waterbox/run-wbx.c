/* run-wbx.c — the host driver that runs core.wbx like the engine does.
 *
 * Built for the HOST (native gcc, links libminiboxhost), so this whole file
 * runs on Linux: natively on CI, inside WSL from a Windows checkout. Flow
 * mirrors session.cpp: create host (memoryLayoutMiB from waterbox.config) ->
 * mount firmware by ID + a "settings" file -> activate -> Init() ->
 * deactivate/seal/activate -> FrameAdvance per frame, pulling GetVideoRaw /
 * GetVideoBgra / GetAudio exactly as the engine would.
 *
 * The guest is mapped in-process at its fixed base, so the pointers its
 * exports return are directly memcpy-able. Out-params the engine would pass
 * as guest pointers are passed NULL here (dims are known: 320x240).
 *
 * Reports the same parity vector as run-native:
 *   run-wbx frames=N stepped=S tstates=T vhash=H bhash=H mhash=H state=H
 * file=(firmware)
 *
 * Sandbox debugging: gdb needs `handle SIGSEGV nostop noprint pass`
 * (miniBox uses SIGSEGV for dirty tracking); a guest fault prints
 * rip=0x36f0... resolved with `addr2line -f -C -e core.wbx <rip>` (the guest
 * links at 0x36f00000000).
 */
#include "minibox.h"
#include "palette.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint64_t fnv1a(const void *data, size_t len, uint64_t h) {
  const unsigned char *p = (const unsigned char *)data;
  while(len--) { h ^= *p++; h *= 1099511628211ULL; }
  return h;
}
static uint64_t mix_hash(uint64_t h, uint64_t v) {
  h ^= v + 0x9e3779b97f4a7c15ULL + (h << 6) + (h >> 2);
  return h;
}

typedef struct { FILE *f; } freader;
static intptr_t file_read(uintptr_t ud, uint8_t *data, uintptr_t size) {
  return (intptr_t)fread(data, 1, (size_t)size, ((freader *)ud)->f);
}
typedef struct { const uint8_t *p; size_t n, pos; } memreader;
static intptr_t mem_reader(uintptr_t ud, uint8_t *data, uintptr_t size) {
  memreader *m = (memreader *)ud;
  size_t take = size < (m->n - m->pos) ? size : (m->n - m->pos);
  memcpy(data, m->p + m->pos, take); m->pos += take; return (intptr_t)take;
}

static uintptr_t proc(mb_host *h, const char *name) {
  mb_return r;
  wbx_get_proc_addr(h, name, &r);
  if(r.error_message[0]) { fprintf(stderr, "run-wbx: no export %s: %s\n", name, r.error_message); exit(2); }
  return r.data;
}
static void die_if_dead(mb_host *h, const char *when) {
  char why[512]; mb_return r;
  wbx_get_death(h, why, sizeof why, &r);
  if(r.data) { fprintf(stderr, "run-wbx: guest dead %s: %s\n", when, why); exit(1); }
}

typedef int (MB_GUEST_ABI *bool_fn)(void);
typedef void (MB_GUEST_ABI *frame_fn)(const uint8_t *, int32_t);
typedef const uint32_t *(MB_GUEST_ABI *bgra_fn)(int32_t *, int32_t *);
typedef const uint8_t *(MB_GUEST_ABI *raw_fn)(void);
typedef uint32_t (MB_GUEST_ABI *audio_fn)(int16_t *, uint32_t);
typedef const int16_t *(MB_GUEST_ABI *audiobuf_fn)(void);
typedef uint64_t (MB_GUEST_ABI *tstates_fn)(void);

static const char *fw_ids[5] = {
  "sos128_0.rom", "sos128_1.rom", "sos48.rom", "service.rom", "dos513f.rom"
};

int main(int argc, char **argv) {
  const char *wbx = NULL;
  const char *resdir = NULL;
  int frames = 600;
  for(int i = 1; i < argc; i++) {
    if(!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
    else if(!strcmp(argv[i], "--resdir") && i + 1 < argc) resdir = argv[++i];
    else if(!strcmp(argv[i], "--help")) {
      printf("usage: run-wbx [--frames N] [--resdir D] <core.wbx>\n");
      return 0;
    } else wbx = argv[i];
  }
  if(!wbx) { fprintf(stderr, "run-wbx: need <core.wbx>\n"); return 1; }

  char rompath[4096];
  const char *romdir = resdir;
  static char resbuf[4096];
  if(!romdir) {
    /* <root>/build/guest/run-wbx -> <root>/extern/upstream/res/rom/ */
    const char *slash = strrchr(argv[0], '/');
    static char bindir[4096];
    if(slash) { size_t n = (size_t)(slash - argv[0]); if(n >= sizeof bindir) n = sizeof bindir - 1; memcpy(bindir, argv[0], n); bindir[n] = 0; }
    else strcpy(bindir, ".");
    snprintf(resbuf, sizeof resbuf, "%s/../../extern/upstream/res/rom/", bindir);
    romdir = resbuf;
  }

  FILE *f = fopen(wbx, "rb");
  if(!f) { fprintf(stderr, "run-wbx: cannot open %s\n", wbx); return 1; }
  /* memoryLayoutMiB from waterbox.config: {sbrk, sealed, invisible, plain, mmap} */
  mb_memory_layout_template layout = {
    .sbrk_size = 16u<<20, .sealed_size = 16u<<20, .invis_size = 64u<<20,
    .plain_size = 64u<<20, .mmap_size = 512u<<20,
  };
  freader fr = { f };
  mb_return r;
  wbx_create_host(&layout, "core.wbx", file_read, (uintptr_t)&fr, &r);
  fclose(f);
  if(r.error_message[0]) { fprintf(stderr, "run-wbx: create: %s\n", r.error_message); return 1; }
  mb_host *h = (mb_host *)r.data;

  for(int i = 0; i < 5; i++) {
    snprintf(rompath, sizeof rompath, "%s%s", romdir, fw_ids[i]);
    wbx_mount_file_path(h, fw_ids[i], rompath, &r);
    if(r.error_message[0]) { fprintf(stderr, "run-wbx: mount %s: %s\n", fw_ids[i], r.error_message); return 1; }
  }
  static const char settings[] = "{}";
  memreader sr = { (const uint8_t *)settings, sizeof settings - 1, 0 };
  wbx_mount_file(h, "settings", mem_reader, (uintptr_t)&sr, false, &r);
  if(r.error_message[0]) { fprintf(stderr, "run-wbx: mount settings: %s\n", r.error_message); return 1; }

  wbx_activate_host(h, &r);
  if(!((bool_fn)proc(h, "Init"))()) { die_if_dead(h, "in Init"); fprintf(stderr, "run-wbx: Init returned false\n"); return 1; }
  wbx_deactivate_host(h, &r);
  wbx_seal(h, &r);
  if(r.error_message[0]) { fprintf(stderr, "run-wbx: seal: %s\n", r.error_message); return 1; }
  wbx_activate_host(h, &r);

  frame_fn FrameAdvance = (frame_fn)proc(h, "FrameAdvance");
  bgra_fn GetVideoBgra = (bgra_fn)proc(h, "GetVideoBgra");
  raw_fn GetVideoRaw = (raw_fn)proc(h, "GetVideoRaw");
  audio_fn GetAudio = (audio_fn)proc(h, "GetAudio");
  audiobuf_fn GetAudioBuf = (audiobuf_fn)proc(h, "GetAudioBuf");
  tstates_fn GetTStates = (tstates_fn)proc(h, "GetTStates");

  const uint64_t FNV_SEED = 1469598103934665603ULL;
  uint64_t vhash = FNV_SEED, bhash = FNV_SEED, mhash = FNV_SEED;
  static uint32_t bgra[320 * 240];
  static int16_t mixed[2048];
  for(int i = 0; i < frames; i++) {
    FrameAdvance(NULL, 0);
    die_if_dead(h, "in FrameAdvance");
    const uint8_t *raw = GetVideoRaw();
    uint8_t rawcopy[320 * 240];
    memcpy(rawcopy, raw, sizeof rawcopy);
    vhash = fnv1a(rawcopy, sizeof rawcopy, vhash);
    const uint32_t *g = GetVideoBgra(NULL, NULL);
    memcpy(bgra, g, sizeof bgra);
    bhash = fnv1a(bgra, sizeof bgra, bhash);
    /* engine path (host buffer through the export) and direct read must agree */
    uint32_t wrote = GetAudio(mixed, 2048);
    const int16_t *direct = GetAudioBuf();
    if(wrote && memcmp(mixed, direct, wrote * sizeof(int16_t)) != 0) {
      fprintf(stderr, "run-wbx: GetAudio disagrees with GetAudioBuf at frame %d\n", i);
      return 1;
    }
    if(wrote)
      mhash = fnv1a(mixed, wrote * sizeof(int16_t), mhash);
  }
  uint64_t tstates = GetTStates();
  uint64_t state = vhash;
  state = mix_hash(state, bhash);
  state = mix_hash(state, mhash);
  state = mix_hash(state, tstates);
  state = mix_hash(state, (uint64_t)frames);
  printf("run-wbx frames=%d stepped=%d tstates=%llu vhash=%016llx bhash=%016llx mhash=%016llx state=%016llx file=(firmware)\n",
      frames, frames,
      (unsigned long long)tstates,
      (unsigned long long)vhash, (unsigned long long)bhash,
      (unsigned long long)mhash, (unsigned long long)state);
  wbx_deactivate_host(h, &r);
  wbx_destroy_host(h, &r);
  return 0;
}
