#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime"
cp -r "$root/ryoku/lockscreen/qylock/quickshell-lockscreen/shim" "$tmp/shim"
cp "$root/tests/lock-power-actions.qml" "$tmp/shell.qml"
# every command the lock may reach records its arguments instead of acting
for cmd in ryoku-host systemctl loginctl; do
    cat > "$tmp/bin/$cmd" <<EOF
#!/bin/sh
printf '%s %s\n' $cmd "\$*" >> "$tmp/calls"
[ "\$1" = show-session ] && echo yes
exit 0
EOF
done
printf '#!/bin/sh\nexec sleep 60\n' > "$tmp/bin/dbus-monitor"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/fprintd-list"
chmod +x "$tmp/bin/"*
: > "$tmp/calls"
PATH="$tmp/bin:$PATH" XDG_SESSION_ID=lock-power-actions XDG_RUNTIME_DIR="$tmp/runtime" \
    HOME="$tmp" QT_QPA_PLATFORM=offscreen \
    timeout 15s qs -p "$tmp/shell.qml" > "$tmp/output" 2>&1 || {
        cat "$tmp/output"
        exit 1
    }
fail=0
for action in reboot poweroff; do
    if ! grep -qx "ryoku-host power $action" "$tmp/calls"; then
        echo "FAIL: the lock's $action button never reached ryoku-host power $action"
        fail=1
    fi
done
# loginctl only answers the session probe; under systemd it has no power verbs
if grep -E '^loginctl (reboot|poweroff)' "$tmp/calls"; then
    echo "FAIL: the lock asked loginctl to power off or reboot"
    fail=1
fi
if [ "$fail" -ne 0 ]; then
    echo "--- recorded calls:"
    grep -v 'show-session' "$tmp/calls" || true
    exit 1
fi
echo "PASS: reboot and poweroff go through ryoku-host power"
