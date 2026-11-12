#!/usr/bin/env bash
# Regression test for 88b35e57 (Python subshell weather refresh recursion).
#
# weather.sh resolves a missing location through location.sh, and location.sh
# starts a background weather refresh after saving a location. Settings are
# written through the ryoku-shell daemon, so while the daemon is unreachable the
# location never persists and every refresh started another one: an unbounded
# chain of weather.sh/location.sh processes, each querying the IP geolocation
# provider.
#
# The test runs the real scripts with the daemon socket absent and stubbed
# network tools, and requires a single geolocation lookup per refresh. It
# writes only under a temporary directory.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts="${RYOKU_PYTHON_SCRIPTS:-$repo/ryoku/shell/quickshell/shell/modules/bar/barstyles/python/scripts}"
[[ -x "$scripts/weather.sh" && -x "$scripts/location.sh" ]] || {
    echo "subshell-python-weather-recursion: scripts not found in $scripts" >&2
    exit 1
}

tmp="$(mktemp -d)"
group=""
cleanup() {
    if [[ -n "$group" ]]; then
        kill -KILL -- "-$group" 2>/dev/null || true
    fi
    rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config/ryoku" "$tmp/cache" "$tmp/state" "$tmp/run"
printf '{}\n' > "$tmp/config/ryoku/shell.json"
log="$tmp/curl.log"
: > "$log"

bash_path="$(command -v bash)"
cat > "$tmp/bin/curl" <<EOF
#!$bash_path
url="\${*: -1}"
printf '%s\n' "\$url" >> "$log"
case "\$url" in
    https://ipapi.co/*)
        printf '%s\n' '{"ip":"192.0.2.1","latitude":51.5,"longitude":-0.12,"city":"Test","region":"Test","country_name":"Test","timezone":"UTC"}'
        ;;
    *)
        exit 22
        ;;
esac
EOF
# The daemon is down: settings.patch never reaches shell.json.
printf '#!%s\nexit 1\n' "$bash_path" > "$tmp/bin/socat"
chmod +x "$tmp/bin/curl" "$tmp/bin/socat"

run_env=(
    env -i
    PATH="$tmp/bin:$PATH"
    HOME="$tmp/home"
    XDG_CONFIG_HOME="$tmp/config"
    XDG_CACHE_HOME="$tmp/cache"
    XDG_STATE_HOME="$tmp/state"
    XDG_RUNTIME_DIR="$tmp/run"
    LANG=C
)

# setsid gives the refresh and everything it starts one process group, so the
# whole chain can be inspected and torn down.
setsid "${run_env[@]}" bash "$scripts/weather.sh" --getdata > "$tmp/out" 2> "$tmp/err" &
group=$!
wait "$group" || true

# Give background refreshes time to run, then count the geolocation lookups.
sleep 4
lookups="$(grep -c 'ipapi.co' "$log" || true)"
alive="$(pgrep -g "$group" 2>/dev/null | wc -l || true)"

if (( lookups != 1 )); then
    echo "subshell-python-weather-recursion: expected 1 geolocation lookup, saw $lookups (still running: $alive)" >&2
    sed 's/^/  curl: /' "$log" | head -20 >&2
    sed 's/^/  stderr: /' "$tmp/err" | head -20 >&2
    exit 1
fi
if (( alive != 0 )); then
    echo "subshell-python-weather-recursion: $alive refresh processes still running" >&2
    exit 1
fi

echo "subshell-python-weather-recursion: one lookup, no refresh chain"
