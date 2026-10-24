#!/usr/bin/env bash
# hermetic test for ryostore-install: the tsv parser carries tier+interactive,
# nautilus-pack and plugin items install/detect through Ryostore's internal guest
# commands, optional-tier items are skipped in a whole-bundle install, and a
# plugin install places the plugin without enabling it (install never activates).
# The actuator prepends $HOME/.local/bin to PATH, so the fakes live there and
# HOME is a temp dir; no network, no pacman, no real shell, no real ryostore.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$here/.."
act="$repo/system/extras/ryostore-install"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

bin="$tmp/.local/bin"
mkdir -p "$bin" "$tmp/cache/bundles/default" "$tmp/cache/bundles/packages" "$tmp/cache/collections/demo" "$tmp/data" "$tmp/run"
printf 'arch\tvoid\tlanes\tnotes\n' >"$tmp/cache/bundles/packages/void.tsv"

# Every item carries a summary, as catalogue items do: an empty field before it
# (an ungated item's managers and reason) must not shift it into another field.
cat >"$tmp/cache/bundles/registry.json" <<'EOF'
{ "bundles": [
  { "id": "demo", "path": "collections/demo", "components": [
    { "type": "package", "name": "corepkg", "detect": "corepkg", "tier": "core", "interactive": false, "summary": "A core tool." },
    { "type": "package", "name": "optpkg", "detect": "optpkg", "tier": "optional", "interactive": false, "summary": "An optional tool." },
    { "type": "script", "name": "pacman-only", "detect": "pacman-only", "tier": "core", "interactive": false, "summary": "Built from the AUR.",
      "packageManagers": ["pacman"], "packageManagersReason": "Needs the AUR." },
    { "type": "nautilus-pack", "name": "video-reformat", "detect": "video-reformat", "tier": "core", "interactive": false, "summary": "Right-click video tools." },
    { "type": "plugin", "name": "creator-deck", "detect": "creator-deck", "tier": "core", "interactive": false, "summary": "A desk widget." } ] },
  { "id": "default", "path": "", "components": [
    { "type": "package", "name": "defaultpkg", "detect": "defaultpkg", "tier": "core", "interactive": false, "summary": "The default tool." } ] },
  { "id": "archonly", "path": "", "packageManagers": ["pacman"], "packageManagersReason": "Only for Arch-based Ryoku.", "components": [
    { "type": "package", "name": "corepkg", "detect": "corepkg", "tier": "core", "interactive": false, "summary": "A core tool." } ] } ] }
EOF
cat >"$tmp/cache/collections/demo/bundle.json" <<'EOF'
{ "id": "demo", "requires": ["multilib", "gpu-lib32"], "items": [
  { "type": "package", "name": "corepkg", "tier": "core", "summary": "A core tool." },
  { "type": "package", "name": "optpkg", "tier": "optional", "summary": "An optional tool." },
  { "type": "script", "name": "pacman-only", "tier": "core", "packageManagers": ["pacman"], "packageManagersReason": "Needs the AUR.", "summary": "Built from the AUR." },
  { "type": "nautilus-pack", "name": "video-reformat", "summary": "Right-click video tools." },
  { "type": "plugin", "name": "creator-deck", "summary": "A desk widget." } ] }
EOF
cat >"$tmp/cache/bundles/default/bundle.json" <<'EOF'
{ "id": "default", "items": [
  { "type": "package", "name": "defaultpkg", "tier": "core", "summary": "The default tool." } ] }
EOF

# fake ryostore: the cache dir, and the internal guest primitives the actuator
# calls. install-guest drops the tracking/plugin manifest the actuator detects;
# remove-guest deletes it. Nothing here enables a plugin: install only places.
cat >"$bin/ryostore" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "internal cache") echo "$tmp/cache"; exit 0 ;;
  "internal package-table") echo "$tmp/cache/bundles/packages/void.tsv"; exit 0 ;;
  "internal bundle")
    case "\$3" in
      demo)    echo "$tmp/cache/collections/demo/bundle.json"; exit 0 ;;
      default) echo "$tmp/cache/bundles/default/bundle.json"; exit 0 ;;
    esac ;;
  "internal installer") echo "$tmp/cache/installers/\$3.sh"; exit 0 ;;
  "internal install-guest")
    case "\$3" in
      plugins)  d="$tmp/data/ryoku/plugins/\$4";  mkdir -p "\$d"; echo '{"defaults":{"host":"sidebarLeft"}}' >"\$d/manifest.json"; exit 0 ;;
      nautilus) d="$tmp/data/ryoku/nautilus/\$4"; mkdir -p "\$d"; echo '{"subdir":"Ryoku Creator"}'         >"\$d/manifest.json"; exit 0 ;;
    esac ;;
  "internal remove-guest")
    case "\$3" in
      plugins)  rm -rf "$tmp/data/ryoku/plugins/\$4";  exit 0 ;;
      nautilus) rm -rf "$tmp/data/ryoku/nautilus/\$4"; exit 0 ;;
    esac ;;
esac
exit 0
EOF

# fake pacman: nothing installed, nothing official -> packages route to the AUR.
cat >"$bin/pacman" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

# Every system-changing helper the actuator can reach is faked and logged, so a
# non-dryrun install below never runs a real package transaction (the real
# ryoku-gpu-lib32 behind a cached sudo once upgraded the whole host).
for helper in sudo ryoku-gpu-lib32 ryoku-pkg-add ryoku-pkg-aur-add ryoku-pkg-remove ryoku-pkg-multilib ryoku-pkg-cachyos; do
  cat >"$bin/$helper" <<EOF
#!/usr/bin/env bash
echo "$helper \$*" >>"$tmp/helpers.log"
exit 0
EOF
done

# fake ryoku-host: the persona comes from FAKE_PKGMGR; on a non-pacman host the
# package table answers status for the edition (corepkg ships there, optpkg
# does not).
cat >"$bin/ryoku-host" <<EOF
#!/usr/bin/env bash
echo "ryoku-host \$* overlay=\${RYOKU_HOST_PKG_OVERLAY:-}" >>"$tmp/helpers.log"
case "\$1" in
  pkgmgr) echo "\${FAKE_PKGMGR:-pacman}"; exit 0 ;;
  pkg)
    shift
    case "\$1" in
      status)
        shift
        for n in "\$@"; do
          case "\$n" in
            corepkg) printf '%s\tavailable\trepo\t\n' "\$n" ;;
            defaultpkg) printf '%s\tinstalled\trepo\t\n' "\$n" ;;
            *) printf '%s\tunavailable\t\tNot packaged for this edition.\n' "\$n" ;;
          esac
        done
        exit 0 ;;
      installed) [[ \$2 == defaultpkg ]]; exit \$? ;;
      why) echo "Answered by pkg why."; exit 0 ;;
    esac ;;
esac
exit 4
EOF

chmod +x "$bin"/*
export HOME="$tmp" XDG_DATA_HOME="$tmp/data" XDG_RUNTIME_DIR="$tmp/run" PATH="$bin:$PATH"

# --- status parses the new item types without corrupting fields ---------------
out="$(bash "$act" status bundle demo)"
grep -q '"type": *"nautilus-pack"' <<<"$out" || fail "nautilus-pack missing from status"
grep -q '"type": *"plugin"' <<<"$out" || fail "plugin missing from status"
out="$(bash "$act" status bundle default)"
grep -q '"name": *"defaultpkg"' <<<"$out" || fail "empty registry path did not use canonical bundle path"

# --- whole-bundle DRYRUN install: core planned, optional skipped --------------
out="$(RYOSTORE_DRYRUN=1 bash "$act" install bundle demo 2>&1)"
grep -q 'corepkg' <<<"$out" || fail "core package not planned"
grep -q 'optpkg' <<<"$out" && fail "optional package planned in whole-bundle install"
grep -qi 'nautilus pack video-reformat' <<<"$out" || fail "nautilus pack not planned"
grep -qi 'plugin creator-deck' <<<"$out" || fail "plugin not planned"
grep -q 'DRYRUN: ensure the 32-bit' <<<"$out" || fail "gpu-lib32 requirement not ensured before install"

# --- optional installs when named as a single item ----------------------------
out="$(RYOSTORE_DRYRUN=1 bash "$act" install item demo optpkg 2>&1)"
grep -q 'optpkg' <<<"$out" || fail "optional package not installed at item scope"

# --- real (non-dryrun) plugin install places the plugin, install-only ---------
bash "$act" install item demo creator-deck >/dev/null 2>&1 || true
[ -f "$tmp/data/ryoku/plugins/creator-deck/manifest.json" ] || fail "plugin not placed on install"

# --- plugin install + removal round-trips through the internal guest commands --
bash "$act" remove item demo creator-deck >/dev/null 2>&1 || true
[ -f "$tmp/data/ryoku/plugins/creator-deck/manifest.json" ] && fail "plugin not removed"

# --- nautilus pack install + removal round-trips ------------------------------
bash "$act" install item demo video-reformat >/dev/null 2>&1 || true
[ -f "$tmp/data/ryoku/nautilus/video-reformat/manifest.json" ] || fail "nautilus pack not installed"
bash "$act" remove item demo video-reformat >/dev/null 2>&1 || true
[ -f "$tmp/data/ryoku/nautilus/video-reformat/manifest.json" ] && fail "nautilus pack not removed"

# --- away from pacman: the edition answers availability, gates hold -----------
# A Void host: ryoku-host names the packages through the catalogue table that
# Ryostore hands over; corepkg ships there, optpkg does not; the pacman-only
# script and the Arch-only bundle are refused with their catalogue reasons.
export FAKE_PKGMGR=xbps
: >"$tmp/helpers.log"
out="$(bash "$act" status bundle demo)"
jq -e '.items[] | select(.name == "corepkg") | .status == "absent"' <<<"$out" >/dev/null || fail "available package not absent on xbps"
jq -e '[.items[] | select(.type == "plugin" or .type == "nautilus-pack") | .status] == ["absent", "absent"]' <<<"$out" >/dev/null \
  || fail "ungated guests not offered on xbps: $out"
jq -e '.items[] | select(.name == "optpkg") | .status == "unavailable" and .reason == "Not packaged for this edition."' <<<"$out" >/dev/null \
  || fail "edition-unavailable package not reported with the batched status reason: $out"
jq -e '.items[] | select(.name == "pacman-only") | .status == "unavailable" and .reason == "Needs the AUR."' <<<"$out" >/dev/null \
  || fail "gated script not unavailable with its reason"
jq -e '.items[] | select(.name == "corepkg") | .summary == "A core tool."' <<<"$out" >/dev/null \
  || fail "summary moved into another field: $out"
grep -q "ryoku-host pkg status corepkg optpkg overlay=$tmp/cache/bundles/packages/void.tsv" "$tmp/helpers.log" \
  || fail "status did not batch packages through ryoku-host with the catalogue table"

: >"$tmp/helpers.log"
out="$(bash "$act" install bundle demo 2>&1 || true)"
grep -q '^ryoku-pkg-add corepkg$' "$tmp/helpers.log" || fail "available package not installed on xbps: $(cat "$tmp/helpers.log")"
grep -q 'ryoku-pkg-multilib' "$tmp/helpers.log" && fail "pacman multilib enabler ran on xbps"
grep -q 'Not on this system: pacman-only (Needs the AUR.)' <<<"$out" || fail "gated item not explained: $out"
jq -e '.items["pacman-only"].status == "unavailable"' "$tmp/run/ryostore/demo.json" >/dev/null || fail "gated item not reported unavailable"

: >"$tmp/helpers.log"
out="$(bash "$act" install bundle archonly 2>&1)" && fail "Arch-only bundle installed on xbps"
grep -q 'Only for Arch-based Ryoku.' <<<"$out" || fail "bundle gate reason missing: $out"
grep -q 'ryoku-pkg' "$tmp/helpers.log" && fail "a package helper ran for a refused bundle"

# On pacman the same gated script is offered like any other.
export FAKE_PKGMGR=pacman
out="$(bash "$act" status bundle demo)"
jq -e '.items[] | select(.name == "pacman-only") | .status == "absent"' <<<"$out" >/dev/null || fail "pacman-only script hidden on pacman"

echo "extras-install: all checks passed"
