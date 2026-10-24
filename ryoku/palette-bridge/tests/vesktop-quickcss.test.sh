#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
helper="$project_root/vesktop/quickcss.sh"
css="$work/custom theme's.css"
palette="$work/palette.css"
printf '@import url("custom.css");\n:root { --user-color: red; }\n' > "$work/custom.css"
cp "$work/custom.css" "$css"
chmod 0600 "$css"
write_palette() {
  printf '/* ryoku-palette-bridge:begin */\n:root { --accent-2: %s; }\n/* ryoku-palette-bridge:end */\n' "$1" > "$palette"
}
original_inode=$(stat -c %i "$css")
write_palette '#112233'
bash "$helper" "$css" "$palette"
[[ $(stat -c %i "$css") == "$original_inode" ]] || {
  printf 'FAIL: palette update replaced the file watched by Vesktop\n' >&2; exit 1
}
write_palette '#aabbcc'
bash "$helper" "$css" "$palette"
bash "$helper" "$css" "$palette"
cat "$work/custom.css" "$palette" > "$work/expected.css"
cmp "$work/expected.css" "$css"
[[ $(stat -c %a "$css") == 600 ]]
[[ $(grep -Fc '/* ryoku-palette-bridge:begin */' "$css") == 1 ]]
cp "$css" "$work/before-failure.css"
if bash "$helper" "$css" "$work/missing.css" 2>"$work/error"; then
  printf 'FAIL: missing palette input was accepted\n' >&2; exit 1
fi
cmp "$work/before-failure.css" "$css"
printf '/* ryoku-palette-bridge:begin */\n:root { --keep: gold; }\n' > "$css"
cp "$css" "$work/incomplete.css"
if bash "$helper" "$css" "$palette" 2>"$work/error"; then
  printf 'FAIL: malformed owned block was overwritten\n' >&2; exit 1
fi
cmp "$work/incomplete.css" "$css"
[[ $(stat -c %a "$css") == 600 ]]
if compgen -G "$work/.ryoku-quickcss.*" >/dev/null; then
  printf 'FAIL: merge left temporary files behind\n' >&2; exit 1
fi
printf 'PASS: QuickCSS updates preserve custom content, modes and failure state\n'
