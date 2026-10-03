#!/bin/sh
# check-wbx.sh — fail a guest with TLS symbols or %fs accesses.
# No thread-local storage: a TLS write with no thread pointer does not fault,
# it lands wherever %fs happens to point. Build with
# -Dthread_local= -D_Thread_local= -D__thread= and fix what breaks.
set -eu
WBX=${1:-./build/guest/core.wbx}
if [ ! -f "$WBX" ]; then echo "check-wbx: $WBX missing (M2 builds it)" >&2; exit 1; fi
if nm "$WBX" 2>/dev/null | grep -E ' [Tt] |__tls|_thread' ; then
  echo "check-wbx: FAILED — TLS symbols present" >&2; exit 1
fi
if objdump -d "$WBX" 2>/dev/null | grep -E '%fs' ; then
  echo "check-wbx: FAILED — %fs accesses present" >&2; exit 1
fi
echo "check-wbx: clean ($WBX)."
