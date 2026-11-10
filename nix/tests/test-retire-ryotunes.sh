#!/usr/bin/env bash
# Retiring legacy Ryotunes exposure: a replica of a real migrated account.
set -euo pipefail
script=${RYOKU_RETIRE_RYOTUNES:?}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export HOME="$work/home" XDG_DATA_HOME="$work/home/.local/share" XDG_CONFIG_HOME="$work/home/.config"
pkg="$work/store/ryotunes-1.2.6"; legacy="$work/store/ryotunesnix-1.2.3"
market="$HOME/.local/state/ryomarket/flake-apps/ryotunes/current/profile"
bin="$HOME/.local/bin"; apps="$XDG_DATA_HOME/applications"; units="$XDG_CONFIG_HOME/systemd/user"
mkdir -p "$pkg/bin" "$legacy/bin" "$market/bin" "$bin" "$apps" "$units/ryotunesd.service.d" \
  "$XDG_DATA_HOME/dev.ryoku.ryotunes" "$XDG_CONFIG_HOME/ryotunes" "$work/bin" "$work/proc"
printf 'db\n' > "$XDG_DATA_HOME/dev.ryoku.ryotunes/ryotunes.sqlite"
printf '{}\n' > "$XDG_CONFIG_HOME/ryotunes/client.json"
for b in ryotunes-qml ryotunesd ryotunes-cli ryotunes-sync ryotunes-diagnostics; do ln -s "$market/bin/$b" "$bin/$b"; done
printf 'ryomarket:ryotunes\n' > "$HOME/.local/state/ryomarket/flake-apps/ryotunes/managed-by"
mkdir -p "$HOME/.local/state/ryoku-hyperion"
ln -s /nix/store/x-ryotunes-hyperion "$HOME/.local/state/ryoku-hyperion/ryotunes-preview"
ln -s /nix/store/x-ryoku-hyperion-nixos-bundle "$HOME/.local/state/ryoku-hyperion/validated-bundle"
ln -s "$HOME/.local/state/ryoku-hyperion/ryotunes-preview/bin/ryotunes-hyperion" "$bin/ryotunes-hyperion"
printf '#!/bin/sh\nexec "$HOME/.local/bin/ryotunes-hyperion"\nexec "$HOME/.local/state/ryomarket/flake-apps/ryotunes/current/profile/bin/ryotunes"\n' > "$bin/ryotunes"
printf '#!/bin/sh\n' > "$bin/ryotunes-soloist-backend"
ln -s "$HOME/.local/state/ryomarket/flake-apps/ryotunes/current/app.desktop" "$apps/dev.ryoku.ryomarket.ryotunes.desktop"
printf '[Desktop Entry]\nExec=ryotunes-hyperion\n' > "$apps/ryotunes-hyperion.desktop"
printf '[Desktop Entry]\nExec=soloist\n' > "$apps/ryotunes-soloist.desktop"
printf '[Service]\n' > "$units/ryotunes-soloist-backend.service"
printf '#!%s\necho "$*" >> %s/systemctl.log\n' "$(command -v bash)" "$work" > "$work/bin/systemctl"; chmod +x "$work/bin/systemctl"

# The profile provides the current Ryotunes (RyoMarket or shipped-apps delivery).
mkdir -p "$HOME/.nix-profile/bin"; : > "$pkg/bin/ryotunesd"
ln -s "$pkg/bin/ryotunesd" "$HOME/.nix-profile/bin/ryotunesd"
run() { PATH="$work/bin:$PATH" RYOKU_PROC_ROOT="$work/proc" bash "$script" "$work/backup"; }
run > "$work/out" 2>&1 || { cat "$work/out"; exit 1; }

fail() { printf 'retire-ryotunes: %s\n' "$*" >&2; cat "$work/out" >&2; exit 1; }
for b in ryotunes ryotunes-qml ryotunesd ryotunes-cli ryotunes-sync ryotunes-diagnostics ryotunes-hyperion; do
  [ ! -e "$bin/$b" ] && [ ! -L "$bin/$b" ] || fail "$b still shadows Hyperion"
  [ -e "$work/backup/ryotunes-legacy/.local/bin/$b" ] || [ -L "$work/backup/ryotunes-legacy/.local/bin/$b" ] || fail "$b was not kept in the backup"
done
[ ! -e "$apps/dev.ryoku.ryomarket.ryotunes.desktop" ] && [ ! -L "$apps/dev.ryoku.ryomarket.ryotunes.desktop" ] || fail "RyoMarket entry kept"
[ ! -e "$apps/ryotunes-hyperion.desktop" ] || fail "preview entry kept"
[ ! -d "$units/ryotunesd.service.d" ] || fail "empty drop-in dir kept"
# Unrelated work and user data are untouched.
[ -f "$bin/ryotunes-soloist-backend" ] && [ -f "$apps/ryotunes-soloist.desktop" ] && [ -f "$units/ryotunes-soloist-backend.service" ] || fail "soloist touched"
[ -f "$XDG_DATA_HOME/dev.ryoku.ryotunes/ryotunes.sqlite" ] && [ -f "$XDG_CONFIG_HOME/ryotunes/client.json" ] || fail "user data touched"
[ ! -e "$HOME/.local/state/ryomarket/flake-apps/ryotunes" ] || fail "RyoMarket Ryotunes profile kept"
[ -d "$work/backup/ryotunes-legacy/.local/state/ryomarket/flake-apps/ryotunes/current/profile/bin" ] || fail "RyoMarket profile not kept in the backup"
[ ! -L "$HOME/.local/state/ryoku-hyperion/ryotunes-preview" ] || fail "preview link kept"
[ -L "$HOME/.local/state/ryoku-hyperion/validated-bundle" ] || fail "unrelated preview state touched"
grep -q 'daemon-reload' "$work/systemctl.log" || fail "units not reloaded"

# Idempotent, and an unknown file is reported, never moved.
printf 'mine\n' > "$bin/ryotunes"
run > "$work/out2" 2>&1
grep -q 'not a Ryoku install' "$work/out2" || { cat "$work/out2"; fail "unknown file not reported"; }
[ "$(cat "$bin/ryotunes")" = mine ] || fail "unknown file moved"

# Process scan: a legacy daemon is stopped, this generation's is not.
sleep 300 & legacy_pid=$!; sleep 300 & current_pid=$!
mkdir -p "$work/proc/$legacy_pid" "$work/proc/$current_pid"
ln -s "$legacy/bin/.ryotunesd-wrapped" "$work/proc/$legacy_pid/exe"; printf 'ryotunesd\0' > "$work/proc/$legacy_pid/cmdline"
ln -s "$pkg/bin/.ryotunesd-wrapped" "$work/proc/$current_pid/exe"; printf 'ryotunesd\0' > "$work/proc/$current_pid/cmdline"
run > "$work/out3" 2>&1
sleep 0.5
! kill -0 "$legacy_pid" 2>/dev/null || fail "legacy daemon still running"
kill -0 "$current_pid" 2>/dev/null || fail "current daemon was stopped"
kill "$current_pid"
grep -q 'restart ryotunesd.socket' "$work/systemctl.log" || fail "socket not rebound after stopping a legacy daemon"
printf 'retire-ryotunes: PASS\n'
