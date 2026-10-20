#!/usr/bin/env bash
# The urgent-update alert end to end in the shell: an updates frame that lists
# an urgent commit raises a critical notification through the shell's own
# server, past Do Not Disturb, and its Update now button starts `ryoku update
# --gui` and opens the Hub's Updates page. ryoku and ryoku-shell are shims that
# log their arguments; a private session bus carries the notification.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/imports/Ryoku" "$tmp/bin" "$tmp/home" "$tmp/config/ryoku" "$tmp/state" "$tmp/cache" "$tmp/data" "$tmp/runtime"
chmod 700 "$tmp/runtime"
# Offscreen there is no compositor behind Quickshell's WindowManager, so the
# copy of Ryoku.Ui gets a Wm that reports one output with nothing fullscreen.
cp -r "$root/ryoku/ui" "$tmp/imports/Ryoku/Ui"
ln -s "$root/ryoku/shell/framebars" "$tmp/imports/Ryoku/FrameBars"
cat > "$tmp/imports/Ryoku/Ui/Singletons/Wm.qml" <<'EOF'
pragma Singleton
import Quickshell

Singleton {
    readonly property string focusedOutput: ""
    function outputHasFullscreen(name) { return false; }
}
EOF
cp "$root/tests/urgent-updates.qml" "$tmp/shell.qml"
: > "$tmp/calls"
for tool in ryoku ryoku-shell; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$tool" "$tmp/calls" > "$tmp/bin/$tool"
    chmod +x "$tmp/bin/$tool"
done
# A bus of its own with no service files, so no installed notification daemon
# is activated in place of the server under test.
cat > "$tmp/bus.conf" <<EOF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$tmp/runtime</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
EOF
env -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u NIRI_SOCKET -u DBUS_SESSION_BUS_ADDRESS \
    PATH="$tmp/bin:$PATH" HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/state" \
    XDG_CACHE_HOME="$tmp/cache" XDG_DATA_HOME="$tmp/data" XDG_RUNTIME_DIR="$tmp/runtime" \
    RYOKU_TEST_CALLS="$tmp/calls" RYOKU_CARD="file://$root/ryoku/shell/quickshell/shell/modules/notifications/NotificationCard.qml" \
    QT_QPA_PLATFORM=offscreen QS_DISABLE_CRASH_HANDLER=1 \
    QML_IMPORT_PATH="$tmp/imports:$root/ryoku/shell/quickshell:${QML_IMPORT_PATH:-}" \
    QML2_IMPORT_PATH="$tmp/imports:$root/ryoku/shell/quickshell:${QML2_IMPORT_PATH:-}" \
    timeout 60s dbus-run-session --config-file="$tmp/bus.conf" -- qs -p "$tmp/shell.qml" > "$tmp/output" 2>&1 || {
        cat "$tmp/output"
        exit 1
    }
if grep -q 'FAIL:' "$tmp/output" || ! grep -q 'PASS:' "$tmp/output"; then
    cat "$tmp/output"
    exit 1
fi
grep 'PASS:' "$tmp/output"
