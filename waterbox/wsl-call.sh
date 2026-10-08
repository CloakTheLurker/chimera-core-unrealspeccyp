#!/bin/sh
# wsl-call.sh — library (source me): run a WSL leg detached and poll for its
# completion marker instead of waiting on the client to exit.
#
# Why: wsl.exe intermittently never exits after its script finishes (the work
# is done — link output complete in the log — but session teardown stalls
# for tens of minutes). Polling the log for a known marker defeats the hang
# regardless of cause; the hung client is then killed and the gate proceeds.
# Retries still terminate Ubuntu first (recovery), like before.
#
# Usage (caller sets WSLROOT, the /mnt/c/... path of the repo root):
#   wsl_call <script> <arg> <marker> <log> <deadline_s>
# <script> is relative to $WSLROOT/tools/wsl/. Returns 0 on marker.
wsl_call() {
  _script="$1"; _arg="$2"; _marker="$3"; _log="$4"; _deadline="$5"
  _attempt=0
  while [ $_attempt -lt 3 ]; do
    _attempt=$((_attempt+1))
    rm -f "$_log"
    export MSYS_NO_PATHCONV=1
    wsl.exe -d Ubuntu -- sh "$WSLROOT/tools/wsl/$_script" "$_arg" < /dev/null > "$_log" 2>&1 &
    _wpid=$!
    # Liveness first: a healthy session logs within ~60s (ninja check, patch
    # lines). A wedged session-start logs nothing — fail it fast (2 min),
    # not after the whole deadline.
    _lived=0
    _waited=0
    while [ $_waited -lt 120 ]; do
      sleep 10
      _waited=$((_waited+10))
      if [ -s "$_log" ]; then _lived=1; break; fi
      if ! kill -0 $_wpid 2>/dev/null; then break; fi
    done
    if [ $_lived -eq 0 ]; then
      echo "wsl_call: $_script produced no output in 120s (attempt $_attempt) — wedged session?" >&2
    else
      _elapsed=0
      while [ $_elapsed -lt $_deadline ]; do
        sleep 15
        _elapsed=$((_elapsed+15))
        if grep -q "$_marker" "$_log" 2>/dev/null; then
          kill $_wpid 2>/dev/null || true
          taskkill.exe /F /PID $_wpid 2>/dev/null || true
          wait $_wpid 2>/dev/null || true
          return 0
        fi
        if ! kill -0 $_wpid 2>/dev/null; then
          wait $_wpid; _code=$?
          echo "wsl_call: $_script exited $_code without marker (attempt $_attempt)" >&2
          break
        fi
      done
      echo "wsl_call: $_script no marker after ${_deadline}s (attempt $_attempt)" >&2
    fi
    echo "wsl_call: terminating Ubuntu and retrying" >&2
    kill $_wpid 2>/dev/null || true
    taskkill.exe /F /PID $_wpid 2>/dev/null || true
    wait $_wpid 2>/dev/null || true
    wsl.exe -t Ubuntu 2>/dev/null || true
    sleep 10
  done
  echo "wsl_call: $_script failed 3 times" >&2
  return 1
}
