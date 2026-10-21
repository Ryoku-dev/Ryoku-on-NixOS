#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
overlay_root="$config_root/ryoku/user_edits/matugen"
overlay_apps="$overlay_root/apps.toml"
live_apps="$config_root/matugen/apps.toml"
if [[ "$config_root" == "$HOME/.config" ]]; then
  # Literal paths written into apps.toml; Matugen expands the tilde.
  # shellcheck disable=SC2088
  matugen_template_root='~/.config/matugen/templates'
else
  matugen_template_root="$config_root/matugen/templates"
fi
want_spotify=false
want_vesktop=false
want_zen=false
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/ryoku/palette-bridge"
ownership_file="$state_root/owned-files.tsv"

usage() {
  printf 'Usage: %s --all | [--spotify] [--vesktop] [--zen]\n' "${0##*/}"
}

while (( $# )); do
  case "$1" in
    --capabilities) printf 'vesktop-preserve-quickcss-v1\n'; exit 0 ;;
    --all) want_spotify=true; want_vesktop=true; want_zen=true ;;
    --spotify) want_spotify=true ;;
    --vesktop) want_vesktop=true ;;
    --zen) want_zen=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if ! $want_spotify && ! $want_vesktop && ! $want_zen; then
  usage >&2
  exit 2
fi

# Render first so an invalid palette cannot leave partial setup.
vesktop_rendered=
if $want_vesktop; then
  command -v jq >/dev/null || { printf 'jq is required for --vesktop\n' >&2; exit 1; }
  source "$project_root/vesktop/quickcss.sh"
  vesktop_root=$(vesktop_config_root "$config_root") || {
    printf 'Vesktop settings not found in %s or %s; start Vesktop once and retry.\n' \
      "$config_root/vesktop/settings" "$(vesktop_flatpak_root)/settings" >&2
    exit 1
  }
  vesktop_temporary=$(mktemp -d)
  trap 'rm -rf "$vesktop_temporary"' EXIT
  vesktop_rendered="$vesktop_temporary/palette.css"
  vesktop_render_palette "$project_root/templates/vesktop-colors.css" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/ryoku/matugen-carrier.json" "$vesktop_rendered"
  vesktop_strip_palette "$vesktop_root/settings/quickCss.css" "$vesktop_temporary/custom.css" 1
fi

prepare_matugen_overlay() {
  install -d "$overlay_root/templates"
  if [[ ! -f "$overlay_apps" ]]; then
    [[ -f "$live_apps" ]] || {
      printf 'Matugen apps file not found: %s\n' "$live_apps" >&2
      exit 1
    }
    install -m 0644 "$live_apps" "$overlay_apps"
  fi
}

record_owned() {
  local integration="$1" path="$2" temporary
  install -d "$state_root"
  temporary=$(mktemp)
  if [[ -f "$ownership_file" ]]; then
    awk -F '\t' -v app="$integration" -v path="$path" '!($1 == app && $2 == path)' "$ownership_file" > "$temporary"
  fi
  printf '%s\t%s\n' "$integration" "$path" >> "$temporary"
  install -m 0600 "$temporary" "$ownership_file"
  rm -f "$temporary"
}

set_matugen_section() {
  local section="$1" input_path="$2" output_path="$3" hook="${4:-}" temporary input_value output_value
  command -v jq >/dev/null || { printf 'jq is required to write Matugen integrations\n' >&2; return 1; }
  input_value=$(jq -Rn --arg value "$input_path" '$value')
  output_value=$(jq -Rn --arg value "$output_path" '$value')
  temporary=$(mktemp)
  awk -v target="[$section]" '
    $0 == target { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' "$overlay_apps" > "$temporary"
  {
    printf '\n[%s]\n' "$section"
    printf 'input_path = %s\n' "$input_value"
    printf 'output_path = %s\n' "$output_value"
    if [[ -n "$hook" ]]; then
      printf 'post_hook = %s\n' "$(jq -Rn --arg hook "$hook" '$hook')"
    fi
  } >> "$temporary"
  install -m 0644 "$temporary" "$overlay_apps"
  rm -f "$temporary"
}

if $want_spotify; then
  command -v spicetify >/dev/null || { printf 'spicetify is required for --spotify\n' >&2; exit 1; }
  install -d "$config_root/spicetify/Extensions"
  install -m 0644 "$project_root/spicetify/ryoku-wallpaper-colors.js" \
    "$config_root/spicetify/Extensions/ryoku-wallpaper-colors.js"
  record_owned spotify "$config_root/spicetify/Extensions/ryoku-wallpaper-colors.js"
  if ! spicetify config extensions | grep -Fxq 'ryoku-wallpaper-colors.js'; then
    spicetify config extensions ryoku-wallpaper-colors.js
  fi
  spicetify apply
  printf 'Installed the Spotify live-palette extension.\n'
fi

if $want_vesktop; then
  command -v jq >/dev/null || { printf 'jq is required for --vesktop\n' >&2; exit 1; }
  settings="$vesktop_root/settings/settings.json"
  [[ -f "$settings" ]] || { printf 'Vesktop settings not found: %s\n' "$settings" >&2; exit 1; }
  prepare_matugen_overlay
  install -m 0644 "$project_root/templates/vesktop-colors.css" "$overlay_root/templates/vesktop-colors.css"
  record_owned vesktop "$overlay_root/templates/vesktop-colors.css"
  merge_root="$state_root/vesktop"
  install -d "$merge_root"
  install -m 0644 "$project_root/vesktop/quickcss.sh" "$merge_root/quickcss.sh"
  install -m 0644 "$vesktop_rendered" "$merge_root/palette.css"
  record_owned vesktop "$merge_root/quickcss.sh"
  record_owned vesktop "$merge_root/palette.css"
  shell_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
  merge_hook="bash $(shell_quote "$merge_root/quickcss.sh") $(shell_quote "$vesktop_root/settings/quickCss.css") $(shell_quote "$merge_root/palette.css")"
  set_matugen_section templates.vesktop \
    "$matugen_template_root/vesktop-colors.css" \
    "$merge_root/palette.css" "$merge_hook"
  # The Ryoku Discord theme (shipped as ryoku-discord.theme.css, or installed by
  # hand as ryoku.theme.css) consumes the same palette roles itself, and
  # stacking Midnight on it changes its layout.
  ryoku_selected=$(jq '(.enabledThemes // []) | any(ascii_downcase | IN("ryoku.theme.css", "ryoku-discord.theme.css"))' "$settings")
  if [[ "$ryoku_selected" != true ]]; then
    install -d "$vesktop_root/themes"
    install -m 0644 "$project_root/vesktop/midnight-ryoku.theme.css" \
      "$vesktop_root/themes/midnight-ryoku.theme.css"
    record_owned vesktop "$vesktop_root/themes/midnight-ryoku.theme.css"
  fi
  temporary=$(mktemp)
  jq --argjson ryoku "$ryoku_selected" '.useQuickCss = true | .enabledThemes = ((.enabledThemes // []) |
    if $ryoku then map(select(. != "midnight-ryoku.theme.css"))
    elif index("midnight-ryoku.theme.css") then . else . + ["midnight-ryoku.theme.css"] end)' \
    "$settings" > "$temporary"
  install -m 0644 "$temporary" "$settings"
  rm -f "$temporary"
  vesktop_write_palette "$vesktop_root/settings/quickCss.css" "$vesktop_rendered"
  printf 'Installed the Vesktop live-palette integration.\n'
fi

if $want_zen; then
  if [[ -n "${ZEN_PROFILE_ROOT:-}" ]]; then
    profile_root="$ZEN_PROFILE_ROOT"
  else
    # Native Zen keeps its profiles in the config directory; the Flathub build
    # keeps them in its own ~/.var/app folder, the only place its sandbox sees.
    for zen_root in "$config_root/zen" \
      "$HOME/.var/app/app.zen_browser.zen/config/zen" \
      "$HOME/.var/app/app.zen_browser.zen/.zen"; do
      profile_root=$(find "$zen_root" -mindepth 2 -maxdepth 2 -name .parentlock -printf '%h\n' -quit 2>/dev/null || true)
      if [[ -z "$profile_root" && -f "$zen_root/profiles.ini" ]]; then
        while IFS= read -r candidate; do
          if [[ -d "$candidate" ]]; then
            profile_root="$candidate"
            break
          fi
        done < <(awk -v root="$zen_root" '
          function saveProfile() {
            if (profile && preferred && path != "")
              defaults[++profileCount] = relative == "0" ? path : root "/" path
          }
          { sub(/\r$/, "") }
          /^\[/ {
            saveProfile()
            profile = ($0 ~ /^\[Profile[^]]+\]$/)
            installation = ($0 ~ /^\[Install[^]]+\]$/)
            path = ""; preferred = 0; relative = "1"
            next
          }
          /^[;#]/ { next }
          index($0, "=") {
            key = substr($0, 1, index($0, "=") - 1)
            value = substr($0, index($0, "=") + 1)
            if (profile && key == "Path") path = value
            if (profile && key == "IsRelative") relative = value
            if (profile && key == "Default" && value == "1") preferred = 1
            if (installation && key == "Default" && value != "")
              installs[++installCount] = substr(value, 1, 1) == "/" ? value : root "/" value
          }
          END {
            saveProfile()
            for (i = 1; i <= installCount; i++) print installs[i]
            for (i = 1; i <= profileCount; i++) print defaults[i]
          }
        ' "$zen_root/profiles.ini")
      fi
      [[ -z "$profile_root" ]] || break
    done
  fi
  [[ -n "${profile_root:-}" && -d "$profile_root" ]] || {
    printf 'Could not identify a Zen profile; set ZEN_PROFILE_ROOT and retry.\n' >&2
    exit 1
  }
  prepare_matugen_overlay
  install -m 0644 "$project_root/templates/zen.css" "$overlay_root/templates/zen.css"
  record_owned zen "$overlay_root/templates/zen.css"
  if [[ "$profile_root" == "$HOME/"* ]]; then
    profile_output="~${profile_root#"$HOME"}/chrome/ryoku-colors.css"
  else
    profile_output="$profile_root/chrome/ryoku-colors.css"
  fi
  set_matugen_section templates.zen "$matugen_template_root/zen.css" "$profile_output"
  install -d "$profile_root/chrome"
  user_chrome="$profile_root/chrome/userChrome.css"
  touch "$user_chrome"
  if ! grep -Fqx '@import "ryoku-colors.css";' "$user_chrome"; then
    temporary=$(mktemp)
    printf '@import "ryoku-colors.css";\n' > "$temporary"
    sed -n '1,$p' "$user_chrome" >> "$temporary"
    install -m 0644 "$temporary" "$user_chrome"
    rm -f "$temporary"
  fi
  record_owned zen "$user_chrome"
  user_js="$profile_root/user.js"
  touch "$user_js"
  temporary=$(mktemp)
  grep -vE 'user_pref\("(toolkit\.legacyUserProfileCustomizations\.stylesheets|zen\.theme\.disable-lightweight)"' "$user_js" > "$temporary" || true
  printf 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);\n' >> "$temporary"
  printf 'user_pref("zen.theme.disable-lightweight", false);\n' >> "$temporary"
  install -m 0644 "$temporary" "$user_js"
  record_owned zen "$user_js"
  rm -f "$temporary"
  printf 'Installed Zen profile wiring. Sign/install zen-extension separately, then restart Zen once.\n'
fi

if $want_vesktop || $want_zen; then
  command -v ryoku >/dev/null || { printf 'ryoku is required to materialize Matugen overlays\n' >&2; exit 1; }
  ryoku materialize
  if command -v ryogami >/dev/null; then
    ryogami wallpaper repaint
  fi
fi
