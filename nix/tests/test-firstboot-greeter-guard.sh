#!/usr/bin/env bash
# The NixOS ryoku-greeter-guard service, checked as systemd starts it: its
# ExecStart under the unit's own PATH. The guard follows login1 session events
# through dbus-monitor and falls back to scanning /proc on a timer when that
# tool is missing, so the packaged wrapper must provide it.
#
# Inputs: GUARD (the unit's ExecStart) and SERVICE_PATH (the unit's PATH).
set -euo pipefail

: "${GUARD:?}" "${SERVICE_PATH:?}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/proc"

# The wrapper sets PATH and then execs the shared guard script. Replay it up to
# that exec to see the environment the guard runs in.
grep -q '^exec ' "$GUARD" || { echo "FAIL: $GUARD does not end in exec" >&2; exit 1; }
sed '/^exec /d' "$GUARD" > "$tmp/env.sh"
found=$(env -i PATH="$SERVICE_PATH" "$BASH" -c '. "$1"; command -v dbus-monitor || true' _ "$tmp/env.sh")
[ -n "$found" ] || {
  echo "FAIL: dbus-monitor is not on the greeter guard's PATH; it would poll /proc instead" >&2
  exit 1
}

# The real unit stays up. No sddm process exists in the fake /proc, so it never
# restarts anything; without a system bus its monitor exits and it keeps
# checking on a timer.
set +e
env -i PATH="$SERVICE_PATH" \
  RYOKU_GREETER_GUARD_PROC="$tmp/proc" \
  RYOKU_GREETER_GUARD_STATE="$tmp/state" \
  RYOKU_GREETER_GUARD_INTERVAL=1 \
  timeout 3 "$GUARD" >"$tmp/out" 2>&1
rc=$?
set -e
cat "$tmp/out"
[ "$rc" -eq 124 ] || { echo "FAIL: guard exited ($rc) instead of running" >&2; exit 1; }

printf 'test-firstboot-greeter-guard: PASS (dbus-monitor: %s)\n' "$found"
