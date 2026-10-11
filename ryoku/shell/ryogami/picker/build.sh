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

cmake -S "$here" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build "$build"

mkdir -p "$dest/Ryoku"
rm -rf "$dest/Ryoku/Ryogami"
cp -a "$build/qml/Ryoku/Ryogami" "$dest/Ryoku/Ryogami"
rm -f "$dest/Ryoku/Ryogami"/*.qrc
