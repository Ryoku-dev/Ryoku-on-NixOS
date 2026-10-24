#!/usr/bin/env bash

set -u
set -o pipefail

json_escape() {
    local value=${1-}
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/ }
    value=${value//$'\r'/ }
    printf '%s' "$value"
}

installed=false
configured=false
version=""

if command -v rclone >/dev/null 2>&1; then
    installed=true
    version=$(rclone version 2>/dev/null | sed -n '1p' || true)
    if rclone listremotes 2>/dev/null | sed 's/[[:space:]]//g' | grep -Fxq 'ii-gdrive:'; then
        configured=true
    fi
fi

printf '{"installed":%s,"configured":%s,"version":"%s"}\n' \
    "$installed" "$configured" "$(json_escape "$version")"
exit 0
