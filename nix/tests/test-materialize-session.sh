#!/usr/bin/env bash
set -euo pipefail
: "${MATERIALIZE:?}" "${BEST_EFFORT:?}" "${RETRY:?}"
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
for ((i = 0; i < 8; i++)); do "$MATERIALIZE" >/dev/null 2>&1 & pids+=($!); done
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
grep -q 'exit=3$' "$HOME/$marker" || fail "failure exit code lost"
grep -q 'exit 3' <<<"$out" || fail "wrong failure exit code logged"
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
# 7. Recovery of a failed first attempt (no session target yet).
# Without a marker the retry is a no-op.
newhome retry-noop
export RYOKU_STUB_LOG=$HOME/stub.log
"$RETRY"; [ ! -e "$RYOKU_STUB_LOG" ] || fail "retry ran without a failure marker"

# Fresh home whose first attempt failed: retry recovers and starts the session.
newhome retry-fresh
export RYOKU_STUB_LOG=$HOME/stub.log
RYOKU_STUB_FAIL=1 "$BEST_EFFORT" >/dev/null 2>&1
[ -s "$HOME/$marker" ] || fail "setup: marker missing"
RYOKU_STUB_KEEP_FAILING=1 "$RETRY" >/dev/null 2>&1 || fail "retry must not fail while still broken"
[ -s "$HOME/$marker" ] || fail "marker cleared although still failing"
[ ! -e "$RYOKU_STUB_LOG" ] || fail "session started although materialization still failing"
"$RETRY" >/dev/null 2>&1 || fail "retry failed"
[ ! -e "$HOME/$marker" ] || fail "marker not cleared by successful retry"
grep -qx session-start "$RYOKU_STUB_LOG" || fail "session not started after recovery"

# Existing session: retry recovers the config but must not restart the session.
newhome retry-live
export RYOKU_STUB_LOG=$HOME/stub.log
RYOKU_STUB_FAIL=1 "$BEST_EFFORT" >/dev/null 2>&1
RYOKU_STUB_TARGET_ACTIVE=1 "$RETRY" >/dev/null 2>&1 || fail "retry failed (live)"
[ ! -e "$HOME/$marker" ] || fail "marker not cleared (live)"
! grep -q session-start "$RYOKU_STUB_LOG" || fail "running session was restarted"
# Hyperion has no standalone migration verb. Setup must still reach QML links.
newhome hyperion
export RYOKU_STUB_HYPERION=1 RYOKU_PROC_ROOT=$HOME/proc
mkdir -p "$RYOKU_PROC_ROOT"
"$HYPERION_MATERIALIZE" >/dev/null 2>&1 || fail "Hyperion materialization failed"
for module in Ryoku/Bus Qt5Compat/GraphicalEffects; do
  [ -d "$HOME/.local/lib/qt6/qml/$module" ] || fail "missing Hyperion QML module $module"
done
unset RYOKU_STUB_HYPERION RYOKU_PROC_ROOT
printf 'test-materialize-session: PASS\n'
