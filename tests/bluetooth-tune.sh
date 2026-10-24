#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TUNE="$ROOT/system/hardware/bluetooth/ryoku-bluetooth-tune"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CONF="$WORK/main.conf"

cat >"$CONF" <<'EOF'
[General]
#Experimental = false
FastConnectable = false
# JustWorksRepairing = never
MultiProfile = single
#AlwaysPairable = false
Name = keep-me

[Policy]
AutoEnable = false
EOF

RYOKU_BT_MAIN_CONF="$CONF" "$TUNE" >/dev/null
cp "$CONF" "$WORK/first-run.conf"
RYOKU_BT_MAIN_CONF="$CONF" "$TUNE" >/dev/null

if ! cmp -s "$WORK/first-run.conf" "$CONF"; then
  printf 'Bluetooth tuning is not idempotent\n' >&2
  diff -u "$WORK/first-run.conf" "$CONF" >&2 || true
  exit 1
fi

assert_one() {
  local setting=$1
  if [[ $(grep -Fxc "$setting" "$CONF") -ne 1 ]]; then
    printf 'expected one %q in tuned main.conf\n' "$setting" >&2
    cat "$CONF" >&2
    exit 1
  fi
}

assert_one 'Experimental = true'
assert_one 'FastConnectable = true'
assert_one 'JustWorksRepairing = always'
assert_one 'MultiProfile = multiple'
assert_one 'AlwaysPairable = true'
assert_one 'AutoEnable = true'
assert_one 'Name = keep-me'

printf 'Bluetooth tuning checks passed\n'
