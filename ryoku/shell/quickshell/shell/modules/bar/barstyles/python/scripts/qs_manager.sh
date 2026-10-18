#!/usr/bin/env bash

# Python's widget-stage router. The ported shell lives inside Ryoku's own
# quickshell instance (`qs -c shell`), so stage commands ride that instance's
# IPC instead of a private quickshell process. The serpantinum workspace and
# app-launcher dispatch are not ported: workspace focus belongs to the
# window-manager seam (compositor keybinds) and the launcher/wallpaper/
# clipboard surfaces are Ryoku's own.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh" 2>/dev/null || true
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/config.sh" 2>/dev/null || true
source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/i18n.sh" 2>/dev/null || true

ACTION="$1"
TARGET="$2"
SUBTARGET="$3"

send_qs_ipc() {
    qs -c shell ipc call main handleCommand "$@" >/dev/null 2>&1
}


QS_NETWORK_CACHE="$QS_CACHE_NETWORK"
NETWORK_MODE_FILE="$QS_NETWORK_CACHE/mode"

QS_GUIDE_CACHE="$QS_CACHE_GUIDE"
GUIDE_MODE_FILE="$QS_GUIDE_CACHE/last_tab.txt"

if [[ "$ACTION" == "close" ]]; then
    send_qs_ipc "close" "" ""
    exit 0
fi

if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    case "$TARGET" in
        network)
            [[ -d "$QS_NETWORK_CACHE" ]] || mkdir -p "$QS_NETWORK_CACHE"
            [[ -n "$SUBTARGET" ]] && echo "$SUBTARGET" > "$NETWORK_MODE_FILE"
            ;;
        guide)
            [[ -d "$QS_GUIDE_CACHE" ]] || mkdir -p "$QS_GUIDE_CACHE"
            [[ -n "$SUBTARGET" ]] && echo "$SUBTARGET" > "$GUIDE_MODE_FILE"
            ;;
        wallpaper)
            ryogami wallpaper ui
            exit 0
            ;;
        applauncher|launcher)
            ryoku-shell launcher
            exit 0
            ;;
        clipboard|clip)
            ryoku-shell clipboard
            exit 0
            ;;
    esac
    send_qs_ipc "$ACTION" "$TARGET" "$SUBTARGET"
    exit 0
fi
