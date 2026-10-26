# Shared WSL paths. Source me: . "$(dirname "$0")/env.sh"
export PATH="$HOME/.local/bin:$PATH"
MESON="meson"
NINJA="ninja"
# The editing trees, as seen from WSL (siblings under Chimera Dev).
WIN_DEV="/mnt/c/Users/admin/Documents/Cursor AI/Chimera Dev"
WIN_CHIMERA="$WIN_DEV/chimera"
WIN_CORE="$WIN_DEV/chimera-core-unrealspeccyp"
# WSL-native space-free mirror of minibox (musl/libstdc++ configures break on
# spaces). mb-sync.sh populates it; guest-link consumes MB_SRC/MB_BUILD.
MB_NATIVE="/home/cloak/mb"
MB_SRC="$MB_NATIVE/minibox"
MB_BUILD="$MB_NATIVE/build"
MINIBOX="$WIN_CHIMERA/extern/chimera-common-minibox"
