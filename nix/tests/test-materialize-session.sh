#!/usr/bin/env bash
set -euo pipefail
: "${MATERIALIZE:?}" "${BEST_EFFORT:?}"
tmp=$(mktemp -d)
trap 'chmod -R u+rwX "$tmp"; rm -rf "$tmp"' EXIT
fail() { printf 'test-materialize-session: FAIL: %s\n' "$*" >&2; exit 1; }

newhome() {
  export HOME=$tmp/$1
  export XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state XDG_DATA_HOME=$HOME/.local/share
  rm -rf "$HOME"; mkdir -p "$HOME"
  unset RYOKU_STUB_FAIL
}
leftovers() { find "$HOME" -name '*.ryoku-nix*' | grep . && return 0 || return 1; }
marker=.local/state/ryoku/nix/materialize-failed

# 1. Fresh home.
newhome fresh
"$MATERIALIZE" >/dev/null 2>&1 || fail "fresh-home materialization failed"
for f in niri/config.kdl niri/autostart.kdl niri/user.kdl; do [ -f "$XDG_CONFIG_HOME/$f" ] || fail "missing $f"; done
[ -w "$XDG_CONFIG_HOME/niri/config.kdl" ] || fail "config.kdl not writable (store mode leaked)"
for m in Ui PluginKit FrameBars Blobs Wm; do [ -d "$HOME/.local/lib/qt6/qml/Ryoku/$m" ] || fail "qml module $m"; done
! leftovers || fail "temporary files left behind"

# 2. Repeat invocation keeps user customisations, restores generation-owned files.
echo '// mine' > "$XDG_CONFIG_HOME/niri/user.kdl"; chmod 0600 "$XDG_CONFIG_HOME/niri/user.kdl"
echo 'tampered' > "$XDG_CONFIG_HOME/niri/config.kdl"
"$MATERIALIZE" >/dev/null 2>&1 || fail "second run failed"
"$MATERIALIZE" >/dev/null 2>&1 || fail "third run failed"
[ "$(cat "$XDG_CONFIG_HOME/niri/user.kdl")" = '// mine' ] || fail "user file overwritten"
[ "$(stat -c %a "$XDG_CONFIG_HOME/niri/user.kdl")" = 600 ] || fail "user file mode changed"
grep -q autostart "$XDG_CONFIG_HOME/niri/config.kdl" || fail "config.kdl not restored"
! leftovers || fail "temporary files left behind"

# 3. Concurrent startup attempts do not collide or corrupt anything.
newhome concurrent
pids=()
for i in 1 2 3 4 5 6 7 8; do "$MATERIALIZE" >/dev/null 2>&1 & pids+=($!); done
for p in "${pids[@]}"; do wait "$p" || fail "concurrent run failed"; done
grep -q autostart "$XDG_CONFIG_HOME/niri/config.kdl" || fail "config.kdl corrupt after concurrent runs"
[ -L "$HOME/.local/lib/qt6/qml/Ryoku/Ui" ] && [ -d "$HOME/.local/lib/qt6/qml/Ryoku/Ui" ] || fail "qml link broken"
! leftovers || fail "temporary files left behind"

# 4. A recoverable failure must not block startup, but must stay visible.
export RYOKU_STUB_FAIL=1
if "$MATERIALIZE" >/dev/null 2>&1; then fail "materializer should fail under fault injection"; fi
out=$("$BEST_EFFORT" 2>&1) || fail "best-effort wrapper blocked startup (existing config)"
grep -q 'ryoku-materialize failed' <<<"$out" || fail "failure was not reported"
grep -q '^<3>' <<<"$out" || fail "failure not logged at error priority"
[ -s "$HOME/$marker" ] || fail "failure marker missing"
grep -q autostart "$XDG_CONFIG_HOME/niri/config.kdl" || fail "existing config damaged by failed run"

# 5. Same failure on a brand-new home still lets the session start.
newhome fresh-fail
export RYOKU_STUB_FAIL=1
"$BEST_EFFORT" >/dev/null 2>&1 || fail "best-effort wrapper blocked startup (fresh home)"
[ -s "$HOME/$marker" ] || fail "marker missing on fresh home"

# 6. Recovery clears the marker.
unset RYOKU_STUB_FAIL
"$BEST_EFFORT" >/dev/null 2>&1 || fail "recovery run failed"
[ ! -e "$HOME/$marker" ] || fail "marker not cleared after success"
[ -f "$XDG_CONFIG_HOME/niri/config.kdl" ] || fail "recovery did not materialize"
printf 'test-materialize-session: PASS\n'
