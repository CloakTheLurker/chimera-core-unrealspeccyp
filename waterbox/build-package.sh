#!/bin/sh
# build-package.sh — the one command CI runs (and nothing else).
# ./waterbox/build-package.sh -r <chimera>
#
# Builds native + guest, runs the gate, stamps version/versionDate into the
# packaged waterbox.config (the commit, and the date of that commit in UTC —
# never the build date, which would make one commit two packages), lays out
# licenses/, and zips dist/unrealspeccyp-<version>.chimeraCore.
# A dependency this script does not build does not exist on a runner.
# The bundle sends each core's stdout to /dev/null, so reproduce silent
# failures with:
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
CHIMERA=$(cd "$CHIMERA" && pwd -P)
export MINIBOX_DIR="$CHIMERA/extern/chimera-common-minibox"

"$HERE/build-native.sh"
"$HERE/build-guest.sh"
"$HERE/run-gate.sh"

COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
WHEN=$(git -C "$ROOT" log -1 --format=%cI 2>/dev/null || echo unknown)
mkdir -p "$ROOT/dist"
cp "$HERE/waterbox.config" "$ROOT/dist/waterbox.config"
cp "$HERE/file_slots.json" "$ROOT/dist/file_slots.json"
cp "$HERE/default_keybinds.json" "$ROOT/dist/default_keybinds.json"
cp "$ROOT/build/guest/core.wbx" "$ROOT/dist/core.wbx"
python3 - "$ROOT/dist/waterbox.config" "$COMMIT" "$WHEN" <<'PY'
import json, sys
path, commit, when = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    cfg = json.load(f)
cfg["version"] = commit
cfg["versionDate"] = when
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print(f"build-package: stamped version={commit} versionDate={when} (commit UTC, not build time)")
PY
python3 "$MINIBOX_DIR/source/guest/package-licenses.py" "$ROOT" "$ROOT/dist"
(cd "$ROOT/dist" && python3 - "$COMMIT" <<'PY'
import json, sys, zipfile
commit = sys.argv[1]
files = ["waterbox.config", "core.wbx", "file_slots.json", "default_keybinds.json"]
import os
for dirpath, _dirs, names in os.walk("licenses"):
    for n in names:
        files.append(os.path.join(dirpath, n))
name = f"unrealspeccyp-{commit}.chimeraCore"
with zipfile.ZipFile(name, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f)
print(f"build-package: dist/{name} assembled ({len(files)} files)")
PY
)
echo "build-package: done."
