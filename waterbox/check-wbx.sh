#!/bin/sh
# check-wbx.sh — guest-image hygiene via miniBox's own check.
# usage: MINIBOX_DIR=... ./waterbox/check-wbx.sh <core.wbx>
set -eu
if [ -z "${MINIBOX_DIR:-}" ]; then
  echo "check-wbx: MINIBOX_DIR is not set (build-package.sh passes it down)" >&2
  exit 1
fi
exec sh "$MINIBOX_DIR/source/guest/check-wbx.sh" "$@"
