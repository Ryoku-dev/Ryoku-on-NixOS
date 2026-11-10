#!/usr/bin/env bash
# Deliver-once rule for Hyperion's shipped apps, against a fake `nix profile`.
set -euo pipefail
script=${RYOKU_SHIPPED_APPS:?}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_STATE_HOME="$work/state" HOME="$work/home"
ref=github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos
mkdir -p "$work/bin" "$HOME"
# The fake profile is a JSON file the stub edits like `nix profile` would.
printf '{"elements":{}}\n' > "$work/profile.json"
cat > "$work/bin/nix" <<SH
#!$(command -v bash)
while [ "\$1" = --extra-experimental-features ]; do shift 2; done
profile="$work/profile.json"
echo "\$*" >> "$work/nix.log"
case "\$1 \$2" in
  "profile list") cat "\$profile" ;;
  "profile add")
    [ -e "$work/offline" ] && exit 1
    name="\${3#*#}"; url="\${3%#*}"; url="\${url//feature\/hyperion/feature%2Fhyperion}"
    jq --arg n "\$name" --arg u "\$url" '.elements[\$n]={active:true,originalUrl:\$u}' "\$profile" > "\$profile.new" && mv "\$profile.new" "\$profile" ;;
  "profile remove")
    jq --arg n "\$3" 'del(.elements[\$n])' "\$profile" > "\$profile.new" && mv "\$profile.new" "\$profile" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$work/bin/nix"
run() { PATH="$work/bin:$PATH" bash "$script" "$ref" ryotunes ryoport ryomanager waifu2x-ncnn-vulkan; }
has() { jq -e --arg n "$1" '.elements[$n]' "$work/profile.json" >/dev/null; }
fail() { printf 'shipped-apps: %s\n' "$*" >&2; cat "$work/nix.log" >&2; exit 1; }

# A legacy RyotunesNix element, and RyoManager already installed from Hyperion.
jq '.elements.ryotunes={active:true,originalUrl:"github:Ryoku-dev/RyotunesNix/8b1b35aa"} | .elements.ryomanager={active:true,originalUrl:"'"$ref"'"}' \
  "$work/profile.json" > "$work/p" && mv "$work/p" "$work/profile.json"
# Offline: nothing installs, nothing is recorded, the run fails for a retry.
touch "$work/offline"
! run >/dev/null 2>&1 || fail "offline run reported success"
grep -qx ryoport "$XDG_STATE_HOME/ryoku/nix/hyperion-shipped-apps" && fail "failed install was recorded"
rm "$work/offline"

run >/dev/null || fail "online run failed"
for app in ryotunes ryoport ryomanager waifu2x-ncnn-vulkan; do has "$app" || fail "$app not delivered"; done
[ "$(jq -r .elements.ryotunes.originalUrl "$work/profile.json")" = "${ref/feature\/hyperion/feature%2Fhyperion}" ] || fail "legacy Ryotunes not replaced"
[ "$(grep -c 'profile add.*ryomanager' "$work/nix.log")" = 0 ] || fail "adopted app reinstalled"

# The user removes waifu2x: it stays removed. Nothing is reinstalled.
jq 'del(.elements["waifu2x-ncnn-vulkan"])' "$work/profile.json" > "$work/p" && mv "$work/p" "$work/profile.json"
: > "$work/nix.log"
run >/dev/null || fail "steady-state run failed"
has waifu2x-ncnn-vulkan && fail "removed app delivered again"
grep -q 'profile \(add\|remove\)' "$work/nix.log" && fail "steady state changed the profile (encoded URL not recognised?)"
printf 'shipped-apps: PASS\n'
