# Shared paths. Source me: . "$(dirname "$0")/env.sh"
#
# Every consumer sits two levels below the repository root (waterbox/tests,
# tools/wsl), so the root is derived from the caller's own directory. No
# checkout path is written down: the same file works from a WSL checkout, a
# Linux clone, and a CI workspace. CORE_ROOT / CHIMERA_ROOT override when a
# caller really is laid out differently.
_env_dir=$(cd "$(dirname "$0")" && pwd -P) || {
  echo "env.sh: cannot resolve the caller's directory" >&2
  exit 1
}
WIN_CORE=${CORE_ROOT:-$(cd "$_env_dir/../.." && pwd -P)}
if [ ! -d "$WIN_CORE/waterbox" ]; then
  echo "env.sh: $WIN_CORE is not the core root (set CORE_ROOT)" >&2
  exit 1
fi
WIN_DEV=$(dirname "$WIN_CORE")
WIN_CHIMERA=${CHIMERA_ROOT:-$WIN_DEV/chimera}
# A CI workspace checks Chimera out inside the core's directory, not beside it.
if [ ! -d "$WIN_CHIMERA/extern/chimera-common-minibox" ] \
   && [ -d "$WIN_CORE/chimera/extern/chimera-common-minibox" ]; then
  WIN_CHIMERA="$WIN_CORE/chimera"
fi
MINIBOX=${MINIBOX_DIR:-$WIN_CHIMERA/extern/chimera-common-minibox}
# The guest toolchain guest-legs.sh links run-wbx against. Under WSL it is a
# space-free native mirror (mb-sync.sh), because musl's configure cannot
# handle the space in "Chimera Dev" — even when build-package.sh passes
# MINIBOX_DIR down. On a runner the miniBox checkout itself is the build
# (configured -Dguest_cpp=true by the guest link).
case "$(uname -r)" in
  *[Mm]icrosoft*) _wsl=1 ;;
  *) _wsl=0 ;;
esac
if [ "$_wsl" = "1" ]; then
  MB_NATIVE=${MB_NATIVE:-$HOME/mb}
  MB_SRC="$MB_NATIVE/minibox"
  MB_BUILD="$MB_NATIVE/build"
elif [ -n "${MINIBOX_DIR:-}" ]; then
  MB_SRC="$MINIBOX_DIR"
  MB_BUILD="$MINIBOX_DIR/build/meson-linux"
else
  MB_NATIVE=${MB_NATIVE:-$HOME/mb}
  MB_SRC="$MB_NATIVE/minibox"
  MB_BUILD="$MB_NATIVE/build"
fi
MESON=${MESON:-meson}
NINJA=${NINJA:-ninja}
