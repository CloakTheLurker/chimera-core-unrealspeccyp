# Shared WSL paths. Source me: . "$(dirname "$0")/env.sh"
export PATH="$HOME/.local/bin:$PATH"
MESON="python3 $HOME/tools/meson-1.7.0/meson.py"
# ~/chimera as seen from WSL (the cp -a build tree).
WIN_CHIMERA="/mnt/c/Users/admin/chimera"
WIN_CORE="/mnt/c/Users/admin/chimera-core-unrealspeccyp"
MINIBOX="$WIN_CHIMERA/extern/chimera-common-minibox"
MB_BUILD="$MINIBOX/build/meson-linux"
