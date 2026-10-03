#!/bin/sh
# run-gate.sh — one command, and every leg says what it compared.
#
# Legs (gates.md: a leg never seen to fail is a leg not tested):
#  m0-build ......... native reference builds headless, no window linkage
#  m0-smoke ......... run-native steps frames on named content
#  m1-stall-300ms ... stall the host 300 ms mid-run; machine must not notice
#  m1-host-clock .... negative control: same leg on the host clock must FAIL
#  m2-sandbox-clean . core.wbx has no TLS/%fs (check-wbx.sh)
# Name the test content: exact file first, glob fallback, print which ran.
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
CONTENT=${USP_TEST_CONTENT:-}
if [ -z "$CONTENT" ]; then
  CONTENT=$(ls "$ROOT"/test-content/* 2>/dev/null | head -n 1 || true)
fi
echo "gate: content: ${CONTENT:-(none yet — M0 smoke needs a distributable snapshot)}"

echo "gate leg m0-build: build-native.sh (headless, no SDL/GL linkage)"
"$HERE/build-native.sh"

if [ -n "$CONTENT" ]; then
  echo "gate leg m0-smoke: run-native --frames 600 --dump-video --pull-audio $CONTENT"
  "$ROOT/build/native/run-native" --frames 600 --dump-video --pull-audio "$CONTENT"
else
  echo "gate leg m0-smoke: SKIPPED — no test content (add a distributable file under test-content/)"
fi

echo "gate leg m1-stall-300ms: PENDING — lands with the M1 virtual-time seam"
echo "gate leg m1-host-clock (negative control): PENDING — must be seen to fail"
echo "gate leg m2-sandbox-clean: PENDING — lands with the M2 guest build"
echo "gate: done (2 pending legs are honest stubs, not green paint)."
