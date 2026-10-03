#!/bin/sh
# build-package.sh — the one command CI runs (and nothing else).
# ./waterbox/build-package.sh -r <chimera>
#
# Builds native + guest, runs the gate, stamps version/versionDate into the
# packaged waterbox.config (the commit, and the date of that commit in UTC —
# never the build date, which would make one commit two packages), and
# assembles dist/ for upload. A dependency this script does not build does
# not exist on a runner. The bundle sends each core's stdout to /dev/null,
# so reproduce silent failures with:
#   env HOME=/tmp/empty ./waterbox/build-package.sh -r <chimera> > /dev/null
set -eu
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/.." && pwd -P)
CHIMERA=""
while [ $# -gt 0 ]; do
  case "$1" in -r|--chimera) CHIMERA="$2"; shift 2;; *) echo "usage: $0 -r <chimera>" >&2; exit 1;; esac
done
if [ -z "$CHIMERA" ]; then echo "build-package: missing -r <chimera>" >&2; exit 1; fi
if [ ! -d "$CHIMERA/extern/chimera-common-minibox" ]; then
  echo "build-package: $CHIMERA/extern/chimera-common-minibox missing (recursive checkout?)" >&2
  exit 1
fi

"$HERE/build-native.sh"
MINIBOX_DIR="$CHIMERA/extern/chimera-common-minibox" "$HERE/build-guest.sh"
"$HERE/run-gate.sh"

COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
WHEN=$(git -C "$ROOT" log -1 --format=%cI 2>/dev/null || echo unknown)
mkdir -p "$ROOT/dist"
cp "$HERE/waterbox.config" "$ROOT/dist/waterbox.config"
echo "build-package: stamping version=$COMMIT versionDate=$WHEN (commit UTC, not build time)"
echo "build-package: dist/ assembled (M0: config only; M2 adds core.wbx + LICENSES.md)."
