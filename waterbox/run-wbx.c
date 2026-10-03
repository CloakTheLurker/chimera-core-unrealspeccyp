/* run-wbx.c — the host driver that runs core.wbx like the engine does (M2).
 *
 * Loads the guest with libminiboxhost, mounts files by name, steps frames,
 * pulls video/audio exactly as session.cpp does. M0/M1: stub only — the
 * file exists so the gate's shape is reviewable. For sandbox debugging:
 * gdb needs `handle SIGSEGV nostop noprint pass` (miniBox uses SIGSEGV for
 * dirty tracking); a guest fault prints rip=0x36f0... resolved with
 * `addr2line -f -C -e core.wbx <rip>` (guest links at 0x36f00000000).
 */
#include <stdio.h>

int main(int argc, char** argv) {
  (void)argc; (void)argv;
  printf("run-wbx (M2 stub): guest driver lands with the M2 guest build.\n");
  return 0;
}
