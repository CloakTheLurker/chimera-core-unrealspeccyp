// run-native.cpp — the reference harness (M0).
//
// Flags for every diagnostic the gate needs: --frames N steps N frames with
// no wall clock (M1 proves a 300 ms host stall changes nothing);
// --dump-video hashes the ULA framebuffer; --pull-audio drains the three
// eDeviceSound sources the way the guest must; --trace-instr counts what the
// machine executed so native-vs-guest compares the machine, not just pixels.
// Audio/video pacing from platform/sdl2/* is deliberately absent: there is
// no eTick, no SDL_Delay, no VideoPaused backpressure here.
#include <cstdio>
#include <cstring>

int main(int argc, char** argv) {
  const char* file = nullptr;
  int frames = 600;
  bool dump_video = false, pull_audio = false, trace_instr = false;
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--frames") && i + 1 < argc) frames = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--dump-video")) dump_video = true;
    else if (!strcmp(argv[i], "--pull-audio")) pull_audio = true;
    else if (!strcmp(argv[i], "--trace-instr")) trace_instr = true;
    else if (!strcmp(argv[i], "--help")) {
      printf("usage: run-native [--frames N] [--dump-video] [--pull-audio] [--trace-instr] <file>\n");
      return 0;
    } else file = argv[i];
  }
  printf("run-native (M0 stub): file=%s frames=%d video=%d audio=%d instr=%d\n",
      file ? file : "(none)", frames, dump_video, pull_audio, trace_instr);
  printf("M0 wires this to eSpeccy via machine.cpp in build-native.sh.\n");
  return file ? 0 : 1;
}
