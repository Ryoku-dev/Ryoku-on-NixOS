#!/usr/bin/env bash
set -euo pipefail
repo=${RYOKU_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}
guard=$repo/ryoku/lockscreen/sddm/ryoku-greeter-guard
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/proc/600"
printf 'sddm\n' > "$tmp/proc/600/comm"
cat > "$tmp/bin/host" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RYOKU_TEST_HOST_LOG"
STUB
cat > "$tmp/bin/logger" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RYOKU_TEST_LOGGER_LOG"
STUB
chmod +x "$tmp/bin/host" "$tmp/bin/logger"
once() {
  RYOKU_GREETER_GUARD_PROC="$tmp/proc" \
  RYOKU_GREETER_GUARD_STATE="$tmp/state" \
  RYOKU_GREETER_GUARD_HOST="$tmp/bin/host" \
  RYOKU_GREETER_GUARD_GRACE=0 \
  RYOKU_GREETER_GUARD_LIMIT=1 \
  RYOKU_TEST_HOST_LOG="$tmp/host.log" \
  RYOKU_TEST_LOGGER_LOG="$tmp/logger.log" \
  PATH="$tmp/bin:$PATH" "$guard" --once
}
once
set +e
once
rc=$?
set -e
[ "$rc" -eq 3 ]
grep -qx 'svc --system restart sddm' "$tmp/host.log"
mkdir -p "$tmp/proc/700"
printf 'sddm-helper\n' > "$tmp/proc/700/comm"
rm -rf "$tmp/state"
: > "$tmp/host.log"
once
[ ! -s "$tmp/host.log" ]
printf 'test-sddm-greeter-guard: PASS\n'
