#!/usr/bin/env bash
# Exercise the packaged CLI with deployed providers and NixOS session entries.
# No compositor, package transaction, privilege escalation or logout is run.
set -euo pipefail
cli=${RYOKU_TEST_CLI:?set RYOKU_TEST_CLI to the built Hyperion CLI}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/hypr" "$tmp/config/niri" "$tmp/sessions" "$tmp/home"

cat > "$tmp/bin/provider" <<STUB
#!$BASH
printf '{}\n'
STUB
cat > "$tmp/bin/ryoku-host" <<STUB
#!$BASH
printf '%s\n' "\$*" >> "\$WM_TEST_HOST_LOG"
exit 1
STUB
cat > "$tmp/bin/sddm-session" <<STUB
#!$BASH
printf '%s\n' "\$*" >> "\$WM_TEST_SESSION_LOG"
exit "\${WM_TEST_SESSION_STATUS:-0}"
STUB
chmod +x "$tmp/bin/"*
cp "$tmp/bin/provider" "$tmp/bin/ryoku-wm-hyprland"
cp "$tmp/bin/provider" "$tmp/bin/ryoku-wm-niri"
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_DATA_DIRS="$tmp/data"
export RYOKU_CONFIG_BASE="$tmp/no-packaged-base" RYOKU_REPO=""
export RYOKU_NIX_SYSTEM_BRIDGE=1 RYOKU_SDDM_ENABLED=1
export RYOKU_SDDM_SESSION_DIR="$tmp/sessions"
export RYOKU_SDDM_SESSION_HELPER="$tmp/bin/sddm-session"
export WM_TEST_HOST_LOG="$tmp/host.log" WM_TEST_SESSION_LOG="$tmp/session.log"
cd "$tmp"

fail() { printf 'test-hyperion-wm-switch: FAIL: %s\n' "$*" >&2; exit 1; }
switch_to() { PATH="$tmp/bin" "$cli" wm use "$1" --keep-previous; }

for target in hyprland niri; do
  if [ "$target" = hyprland ]; then export RYOKU_WM=niri; else export RYOKU_WM=hyprland; fi
  printf '[Desktop Entry]\nExec=/nix/store/test-session\n' > "$tmp/sessions/ryoku-$target.desktop"
  if [ -n "${RYOKU_TEST_HUB:-}" ]; then
    PATH="$tmp/bin" "$RYOKU_TEST_HUB" wm preview "$target" > "$tmp/preview" 2>&1 || fail "Hub preview failed"
    grep -Eq '"selectable"[[:space:]]*:[[:space:]]*true' "$tmp/preview" || fail "Hub rejected deployed $target"
    grep -Eq '"deployed"[[:space:]]*:[[:space:]]*true' "$tmp/preview" || fail "Hub did not detect deployed $target"
  fi
  rm -f "$WM_TEST_HOST_LOG" "$WM_TEST_SESSION_LOG"
  switch_to "$target" > "$tmp/output" 2>&1 || { cat "$tmp/output"; fail "$target switch failed"; }
  grep -qx "$target" "$WM_TEST_SESSION_LOG" || fail "$target was not preselected"
  grep -q "SDDM will preselect $target" "$tmp/output" || fail "missing SDDM result"
  [ ! -s "$WM_TEST_HOST_LOG" ] || fail "deployed target consulted the package manager"

  rm "$tmp/sessions/ryoku-$target.desktop"
  rm -f "$WM_TEST_SESSION_LOG"
  if switch_to "$target" > "$tmp/output" 2>&1; then fail "missing $target session accepted"; fi
  [ ! -e "$WM_TEST_SESSION_LOG" ] || fail "unavailable session preselected"
  grep -q "cannot switch to $target" "$tmp/output" || fail "missing refusal reason"
  if [ -n "${RYOKU_TEST_HUB:-}" ]; then
    PATH="$tmp/bin" "$RYOKU_TEST_HUB" wm preview "$target" > "$tmp/preview" 2>&1 || fail "Hub unavailable preview failed"
    grep -Eq '"selectable"[[:space:]]*:[[:space:]]*false' "$tmp/preview" || fail "Hub accepted missing $target session"
  fi
done

# Failure to preselect leaves the deployed compositor usable with manual login.
export RYOKU_WM=hyprland WM_TEST_SESSION_STATUS=1
printf '[Desktop Entry]\n' > "$tmp/sessions/ryoku-niri.desktop"
switch_to niri > "$tmp/output" 2>&1 || fail "preselection failure rejected ready compositor"
grep -q 'Select niri manually' "$tmp/output" || fail "missing manual selection fallback"

# Another display manager does not call the SDDM helper.
export RYOKU_SDDM_ENABLED=0
rm -f "$WM_TEST_SESSION_LOG"
switch_to niri > "$tmp/output" 2>&1 || fail "switch with SDDM disabled failed"
[ ! -e "$WM_TEST_SESSION_LOG" ] || fail "SDDM helper called while disabled"
printf 'test-hyperion-wm-switch: PASS\n'
