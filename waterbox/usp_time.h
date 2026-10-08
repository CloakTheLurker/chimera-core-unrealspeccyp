// usp_time.h — the virtual-time seam (M1).
//
// Audit result: the machine (eSpeccy + devices + Z80) never asks the wall
// what time it is. All its timing is instruction-counted (t-states per
// frame, TICK_F fixed-point audio resampling, tact-scheduled tape pulses).
// The ONLY wall clocks in upstream live in the platform pacing layer:
//
//   platform/sdl2/sdl2.cpp  eTick + SDL_Delay(3) frame pacing (~15ms floor)
//   platform/sdl2/sdl2_audio.cpp  UpdateAudio: buffer-full backpressure calls
//                           Handler()->VideoPaused(), which GATES OnLoop —
//                           the machine steps only when audio drains in wall
//                           time. That is wall-clock coupling of stepping.
//   tools/tick.h (+linux/tick_gtod.h gettimeofday / win/tick_qpc.h QPC)
//                           the tick source behind both.
//
// So the seam is the pacing layer, not the machine: this header provides the
// two clocks side by side plus the pacer that mirrors the SDL platform's
// coupling. The harness (--clock virtual, the default) never paces and never
// drops: frames are bought with executed instructions only, and idle (a host
// stall) jumps to the next scheduled deadline by doing nothing at all. The
// --clock host mode replays the platform bug faithfully (pad each frame to
// wall 20ms; drop machine frames when >1 frame late, like VideoPaused
// gating) so the gate's negative control has real teeth.
#pragma once
#include <stdint.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/time.h>
#include <time.h>
#endif

static inline uint64_t usp_host_ms() {
#ifdef _WIN32
  return (uint64_t)GetTickCount64();
#else
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000;
#endif
}

static inline void usp_sleep_ms(unsigned ms) {
  if(!ms)
    return;
#ifdef _WIN32
  Sleep(ms);
#else
  struct timespec ts;
  ts.tv_sec = ms / 1000;
  ts.tv_nsec = (long)(ms % 1000) * 1000000L;
  nanosleep(&ts, NULL);
#endif
}

// The two clocks. The machine advances the virtual one (via TStates); the
// wall advances the host one. The harness must never let the host one gate
// stepping — except in --clock host, which exists to prove why.
struct UspClock {
  virtual uint64_t NowMs() const = 0;
  virtual ~UspClock() {}
};

struct HostClock : public UspClock {
  virtual uint64_t NowMs() const { return usp_host_ms(); }
};

struct VirtualClock : public UspClock {
  uint64_t t_states;
  uint64_t tacts_per_frame;
  uint32_t frames_per_second;
  VirtualClock(uint64_t t = 0, uint64_t tpf = 71680, uint32_t fps = 50)
    : t_states(t), tacts_per_frame(tpf), frames_per_second(fps) {}
  void AdvanceFrames(uint64_t n = 1) { t_states += n * tacts_per_frame; }
  virtual uint64_t NowMs() const { return t_states * 1000 / (tacts_per_frame * frames_per_second); }
};

// Mirrors the SDL platform's wall coupling: pad every stepped frame out to a
// wall 20ms (50Hz). Mild lateness (coarse host timers) just skips the pad
// sleep and catches up by stepping; only sustained lateness (beyond
// drop_late_ms, 5 frames) DROPs the machine step
// to catch up (the VideoPaused-gating equivalent). Drops are counted and
// reported; a run with drops is a run the wall visibly perturbed.
class FramePacer {
public:
  explicit FramePacer(uint64_t frame_ms = 20, uint64_t drop_late_ms = 100)
    : frame_ms_(frame_ms), drop_late_ms_(drop_late_ms), deadline_(0), dropped_(0), started_(false) {}
  void Start() {
    deadline_ = clock_.NowMs() + frame_ms_;
    started_ = true;
  }
  // True: step the machine. False: DROP — skip the step (catch-up).
  bool Next() {
    uint64_t now = clock_.NowMs();
    if(now > deadline_ + drop_late_ms_) {
      deadline_ += frame_ms_;
      ++dropped_;
      return false;
    }
    return true;
  }
  // Call after the machine stepped: sleep the wall remainder, advance.
  void Stepped() {
    uint64_t now = clock_.NowMs();
    if(now < deadline_)
      usp_sleep_ms((unsigned)(deadline_ - now));
    deadline_ += frame_ms_;
  }
  unsigned dropped() const { return dropped_; }
private:
  HostClock clock_;
  uint64_t frame_ms_;
  uint64_t drop_late_ms_;
  uint64_t deadline_;
  unsigned dropped_;
  bool started_;
};
