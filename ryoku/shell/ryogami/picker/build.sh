#!/usr/bin/env bash
# Usage: build.sh <qml-import-dir>; RYOGAMI_PICKER_BUILD overrides the build directory.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dest="${1:?usage: build.sh <qml-import-dir>}"
build="${RYOGAMI_PICKER_BUILD:-$here/build}"

for tool in cmake ninja; do
  command -v "$tool" >/dev/null 2>&1 || {
    advice="$(ryoku-host pkg advice cmake ninja qt6-shadertools 2>/dev/null || printf '%s' 'install cmake, ninja, and Qt shader tools')"
    printf 'build.sh: error: %s is required (%s)\n' "$tool" "$advice" >&2
    exit 1
  }
done

# The GPU card list includes <vulkan/vulkan.h>. A header is not a command, so the
# loop above cannot see it missing, and a checkout that lacks it used to compile
# for half a minute and then stop on an include error naming no package. The
# packaged builds carry it; a source tree is on its own.
# `ryoku-host pkg advice` only answers for packages inside the installed closure,
# and a build dependency sits outside it, so name the package here instead.
# CXX may carry a wrapper or flags ("ccache g++"), as cmake accepts below.
read -r -a cxx <<<"${CXX:-c++}"
if ! printf '#include <vulkan/vulkan.h>\nint main(void){return 0;}\n' \
  | "${cxx[@]}" -fsyntax-only -x c++ - >/dev/null 2>&1; then
  printf 'build.sh: error: the Vulkan headers are required (vulkan-headers on Arch and Fedora, Vulkan-Headers on Void)\n' >&2
  exit 1
fi

cmake -S "$here" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$build"

mkdir -p "$dest/Ryoku"
rm -rf "$dest/Ryoku/Ryogami"
cp -a "$build/qml/Ryoku/Ryogami" "$dest/Ryoku/Ryogami"
rm -f "$dest/Ryoku/Ryogami"/*.qrc
