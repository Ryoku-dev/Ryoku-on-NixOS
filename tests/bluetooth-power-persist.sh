#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
POWER="$ROOT/system/hardware/bluetooth/ryoku-bluetooth-power"
RESET="$ROOT/system/hardware/bluetooth/ryoku-bluetooth-reset"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/systemd"
LOG="$WORK/commands"
LIVE="$WORK/live"
STATE="$WORK/state/bluetooth-power"

cat >"$WORK/bin/rfkill" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'rfkill %s\n' "$*" >>"$RYOKU_TEST_LOG"
case ${1:-} in
  block) printf 'off\n' >"$RYOKU_TEST_LIVE" ;;
esac
EOF
cat >"$WORK/bin/bluetoothctl" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'bluetoothctl %s\n' "$*" >>"$RYOKU_TEST_LOG"
case ${1:-} in
  power)
    printf '%s\n' "$2" >"$RYOKU_TEST_LIVE"
    ;;
  show)
    if [[ $(cat "$RYOKU_TEST_LIVE" 2>/dev/null || printf off) == on ]]; then
      printf 'Powered: yes\n'
    else
      printf 'Powered: no\n'
    fi
    ;;
esac
EOF
cat >"$WORK/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'systemctl %s\n' "$*" >>"$RYOKU_TEST_LOG"
printf 'on\n' >"$RYOKU_TEST_LIVE"
EOF
cat >"$WORK/bin/sv" <<'EOF'
#!/usr/bin/env bash
set -eu
printf 'sv %s\n' "$*" >>"$RYOKU_TEST_LOG"
printf 'on\n' >"$RYOKU_TEST_LIVE"
EOF
cat >"$WORK/bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -eu
shift
exec "$@"
EOF
chmod +x "$WORK/bin/"*

export PATH="$WORK/bin:$PATH"
export RYOKU_TEST_LOG="$LOG"
export RYOKU_TEST_LIVE="$LIVE"
export RYOKU_BLUETOOTH_STATE_FILE="$STATE"
export RYOKU_BLUETOOTH_POWER_BIN="$POWER"

assert_eq() {
  local want=$1 got=$2 label=$3
  if [[ $got != "$want" ]]; then
    printf 'FAIL: %s: want %q, got %q\n' "$label" "$want" "$got" >&2
    exit 1
  fi
}

# No saved choice is a fresh install, which deliberately defaults to on.
printf 'off\n' >"$LIVE"
"$POWER" restore
assert_eq on "$(cat "$LIVE")" 'fresh install default'

# Turning Bluetooth off records the choice and soft-blocks the radio.
"$POWER" off
assert_eq off "$(cat "$STATE")" 'saved off choice'
assert_eq off "$(cat "$LIVE")" 'live off choice'

# Simulate systemd restarting bluetoothd with AutoEnable=true. Restore must win.
"$RESET"
assert_eq off "$(cat "$LIVE")" 'off after systemd login reset'

# Void has no systemd-rfkill boot restore, so its login reset applies the same
# per-user state immediately after restarting bluetoothd through runit.
RYOKU_SYSTEMD_RUNTIME="$WORK/no-systemd" "$RESET"
assert_eq off "$(cat "$LIVE")" 'off after runit login reset'

# An explicit on choice survives the same reset and remains the default action.
"$POWER" on
assert_eq on "$(cat "$STATE")" 'saved on choice'
"$RESET"
assert_eq on "$(cat "$LIVE")" 'on after systemd login reset'

printf 'bluetooth power persistence checks passed\n'
