#!/usr/bin/env bash
set -euo pipefail

script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
data_root="${XDG_DATA_HOME:-$HOME/.local/share}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/ryoku/palette-bridge"
ownership_file="$state_root/owned-files.tsv"
bridge_apps="$config_root/ryoku/palette-bridge/matugen.toml"
legacy_apps="$config_root/ryoku/user_edits/matugen/apps.toml"
live_apps="$config_root/matugen/apps.toml"
want=

usage() { printf 'Usage: %s --spotify | --vesktop | --zen\n' "${0##*/}"; }

case "${1:-}" in
  --spotify) want=spotify ;;
  --vesktop) want=vesktop ;;
  --zen) want=zen ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

remove_owned_file() {
  local path="$1"
  [[ -f "$path" ]] && rm -f -- "$path"
}

remove_matugen_section() {
  local section="$1" temporary
  [[ -f "$bridge_apps" ]] || return 0
  temporary=$(mktemp)
  awk -v target="[$section]" '
    $0 == target { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' "$bridge_apps" > "$temporary"
  install -m 0644 "$temporary" "$bridge_apps"
  rm -f "$temporary"
}

remove_legacy_matugen_section() {
  local section="$1" temporary base
  [[ -f "$legacy_apps" ]] || return 0
  grep -Fqx "[$section]" "$legacy_apps" || return 0
  temporary=$(mktemp)
  awk -v target="[$section]" '
    $0 == target { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' "$legacy_apps" > "$temporary"
  base=/usr/share/ryoku/config/matugen/apps.toml
  if [[ -f "$script_root/../shell/matugen/apps.toml" ]]; then
    base="$script_root/../shell/matugen/apps.toml"
  fi
  if [[ -f "$base" ]] &&
      [[ "$(awk 'NF { print }' "$temporary")" == "$(awk 'NF { print }' "$base")" ]]; then
    rm -f "$legacy_apps"
    install -Dm0644 "$base" "$live_apps"
  else
    install -m 0644 "$temporary" "$legacy_apps"
    install -Dm0644 "$temporary" "$live_apps"
  fi
  rm -f "$temporary"
}


helper="$script_root/vesktop/quickcss.sh"
if [[ ! -f "$helper" ]]; then
  helper="$script_root/../share/ryoku/palette-bridge/vesktop/quickcss.sh"
fi
# shellcheck source=ryoku/palette-bridge/vesktop/quickcss.sh
source "$helper"

case "$want" in
  spotify)
    if command -v spicetify >/dev/null; then
      spicetify config extensions ryoku-wallpaper-colors.js- || true
      spicetify apply || true
    fi
    ;;
  vesktop)
    vesktop_root=$(vesktop_config_root "$config_root") || vesktop_root="$config_root/vesktop"
    vesktop_write_palette "$vesktop_root/settings/quickCss.css"
    remove_matugen_section templates.vesktop
    remove_legacy_matugen_section templates.vesktop
    settings="$vesktop_root/settings/settings.json"
    if [[ -f "$settings" ]] && command -v jq >/dev/null; then
      temporary=$(mktemp)
      jq '.enabledThemes = ((.enabledThemes // []) | map(select(. != "midnight-ryoku.theme.css")))' "$settings" > "$temporary"
      install -m 0644 "$temporary" "$settings"
      rm -f "$temporary"
    fi
    ;;
  zen)
    remove_matugen_section templates.zen
    remove_legacy_matugen_section templates.zen
    ;;
esac

if [[ -f "$ownership_file" ]]; then
  while IFS=$'\t' read -r integration path; do
    [[ "$integration" == "$want" ]] || continue
    case "$want:$path" in
      spotify:"$config_root"/spicetify/Extensions/ryoku-wallpaper-colors.js|\
      vesktop:"$data_root"/ryoku/palette-bridge/templates/vesktop-colors.css|\
      vesktop:"$config_root"/ryoku/user_edits/matugen/templates/vesktop-colors.css|\
      vesktop:"$config_root"/vesktop/themes/midnight-ryoku.theme.css|\
      vesktop:"$(vesktop_flatpak_root)"/themes/midnight-ryoku.theme.css|\
      vesktop:"$state_root"/vesktop/quickcss.sh|\
      vesktop:"$state_root"/vesktop/palette.css|\
      zen:"$data_root"/ryoku/palette-bridge/templates/zen.css|\
      zen:"$config_root"/ryoku/user_edits/matugen/templates/zen.css)
        remove_owned_file "$path"
        ;;
      zen:*/chrome/ryoku-colors.css)
        remove_owned_file "$path"
        ;;
      zen:*/chrome/userChrome.css)
        temporary=$(mktemp)
        grep -Fvx '@import "ryoku-colors.css";' "$path" > "$temporary" || true
        install -m 0644 "$temporary" "$path"
        rm -f "$temporary"
        ;;
      zen:*/user.js)
        temporary=$(mktemp)
        grep -vE 'user_pref\("(toolkit\.legacyUserProfileCustomizations\.stylesheets", true|zen\.theme\.disable-lightweight", false)\);' "$path" > "$temporary" || true
        install -m 0644 "$temporary" "$path"
        rm -f "$temporary"
        ;;
    esac
  done < "$ownership_file"
  temporary=$(mktemp)
  awk -F '\t' -v app="$want" '$1 != app' "$ownership_file" > "$temporary"
  install -m 0600 "$temporary" "$ownership_file"
  rm -f "$temporary"
fi

printf 'Removed the %s integration files owned by Ryoku Palette Bridge.\n' "$want"
