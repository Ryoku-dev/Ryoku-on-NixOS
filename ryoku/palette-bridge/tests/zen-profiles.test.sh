#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/ryoku-zen-profiles.XXXXXX")
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin"
for tool in ryoku ryogami; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/$tool"
  chmod +x "$test_root/bin/$tool"
done

for scenario in relative absolute install-relative install-absolute crlf quoted fallback running override; do
  config="$test_root/$scenario/config"
  zen="$config/zen"
  profile="$zen/default.profile"
  mkdir -p "$zen" "$config/matugen"
  printf '[config]\n' > "$config/matugen/apps.toml"
  override=
  case "$scenario" in
    relative)
      printf '[Profile0]\nDefault=1\nPath=default.profile\nIsRelative=1\n' > "$zen/profiles.ini"
      ;;
    absolute|crlf|quoted)
      profile="$test_root/$scenario/external profile=one"
      if [[ $scenario == quoted ]]; then
        profile="$test_root/$scenario/external \"profile\\one"
      fi
      printf '[Profile0]\nDefault=1\nIsRelative=0\nPath=%s\n' "$profile" > "$zen/profiles.ini"
      if [[ $scenario == crlf ]]; then
        sed -i 's/$/\r/' "$zen/profiles.ini"
      fi
      ;;
    install-relative)
      printf '[Profile0]\nPath=default.profile\nIsRelative=1\n\n[InstallHASH]\nDefault=default.profile\nLocked=1\n' > "$zen/profiles.ini"
      ;;
    install-absolute)
      profile="$test_root/$scenario/external profile"
      printf '[InstallHASH]\nDefault=%s\nLocked=1\n\n[Profile0]\nPath=ignored.profile\nDefault=1\n' "$profile" > "$zen/profiles.ini"
      mkdir -p "$zen/ignored.profile"
      ;;
    fallback)
      printf '[InstallHASH]\nDefault=missing.profile\n\n[Profile0]\nPath=default.profile\nDefault=1\n' > "$zen/profiles.ini"
      ;;
    running|override)
      mkdir -p "$zen/ignored.profile"
      printf '[Profile0]\nPath=ignored.profile\nDefault=1\n' > "$zen/profiles.ini"
      if [[ $scenario == running ]]; then
        mkdir -p "$profile"
        touch "$profile/.parentlock"
      else
        profile="$test_root/$scenario/explicit profile"
        override="$profile"
        touch "$zen/ignored.profile/.parentlock"
      fi
      ;;
  esac
  mkdir -p "$profile"
  XDG_CONFIG_HOME="$config" XDG_STATE_HOME="$test_root/$scenario/state" \
    ZEN_PROFILE_ROOT="$override" PATH="$test_root/bin:$PATH" \
    "$project_root/install-integrations.sh" --zen > "$test_root/$scenario/output" 2>&1 || {
      cat "$test_root/$scenario/output" >&2
      printf 'FAIL: Zen profile selection: %s\n' "$scenario" >&2
      exit 1
    }
  grep -Fxq '@import "ryoku-colors.css";' "$profile/chrome/userChrome.css"
  expected_output="output_path = $(jq -Rn --arg path "$profile/chrome/ryoku-colors.css" '$path')"
  grep -Fxq "$expected_output" "$config/ryoku/user_edits/matugen/apps.toml"
  [[ ! -e "$zen/ignored.profile/chrome/userChrome.css" ]]
done

# An explicit missing profile must fail rather than silently modifying a default.
if XDG_CONFIG_HOME="$config" XDG_STATE_HOME="$test_root/missing-state" \
  ZEN_PROFILE_ROOT="$test_root/nonexistent" PATH="$test_root/bin:$PATH" \
  "$project_root/install-integrations.sh" --zen > /dev/null 2>&1; then
  printf 'FAIL: missing explicit Zen profile was accepted\n' >&2
  exit 1
fi
# The Flathub build keeps its profiles in its own ~/.var/app folder, under .zen
# or its XDG config. With no native profile, setup finds the default one there.
for flatpak_root in .var/app/app.zen_browser.zen/.zen .var/app/app.zen_browser.zen/config/zen; do
  home="$test_root/flatpak-${flatpak_root//\//-}"
  zen="$home/$flatpak_root"
  mkdir -p "$zen/flat.default" "$home/.config/matugen"
  printf '[config]\n' > "$home/.config/matugen/apps.toml"
  printf '[Profile0]\nPath=flat.default\nIsRelative=1\nDefault=1\n' > "$zen/profiles.ini"
  HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/state" \
    PATH="$test_root/bin:$PATH" "$project_root/install-integrations.sh" --zen > "$home/output" 2>&1 || {
      cat "$home/output" >&2
      printf 'FAIL: Flathub Zen profile: %s\n' "$flatpak_root" >&2
      exit 1
    }
  grep -Fxq '@import "ryoku-colors.css";' "$zen/flat.default/chrome/userChrome.css"
  grep -Fxq "output_path = \"~/$flatpak_root/flat.default/chrome/ryoku-colors.css\"" \
    "$home/.config/ryoku/user_edits/matugen/apps.toml"
done
printf 'PASS: Zen profile defaults, absolute paths, and explicit/running precedence\n'
