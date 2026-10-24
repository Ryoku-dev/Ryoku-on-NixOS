#!/usr/bin/env bash

# Python's settings helper: settings live in the `python` key of Ryoku's
# shell.json. Reads are plain jq against the file; writes NEVER touch the file
# directly -- the ryoku-shell daemon is the one writer of shell.json, so a
# script's write rides its control socket as a settings.patch call.

source "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/caching.sh"

CONFIG_SETTINGS_JSON="${QS_SETTINGS:-${XDG_CONFIG_HOME:-$HOME/.config}/ryoku/shell.json}"
RYOKU_SHELL_SOCK="${XDG_RUNTIME_DIR:-/tmp}/ryoku-shell.sock"

_py_root() {
    # The python subtree of shell.json, or {} when unset.
    local val
    val="$(jq -c '.python // {}' "$CONFIG_SETTINGS_JSON" 2>/dev/null)"
    [ -z "$val" ] && val='{}'
    printf '%s' "$val"
}

get_setting() {
    local key="$1"
    local fallback="${2:-}"
    local val
    # Script settings are objects; a stored non-object (a stale or corrupt
    # value) reads as missing so callers never pipe a bare string to jq.
    val="$(_py_root | jq -c --arg k "$key" 'if has($k) and (.[$k] | type) == "object" then .[$k] else null end' 2>/dev/null)"
    if [[ -z "$val" || "$val" == "null" ]]; then
        printf '%s' "$fallback"
    else
        printf '%s' "$val"
    fi
}

_py_patch() {
    local payload="$1"
    printf 'call settings.patch %s\n' "$payload" | timeout 3 socat - UNIX-CONNECT:"$RYOKU_SHELL_SOCK" >/dev/null 2>&1
}

# A script's write goes to the daemon, which persists and broadcasts it; the
# running shell's own Config mirror updates on the echo, so nothing here needs
# to worry about concurrent writers. The patched subtree is the merged root,
# so a leaf write never drops its siblings.
set_setting() {
    local key="$1"
    local value="$2"

    local json_value
    if echo "$value" | jq -e . > /dev/null 2>&1; then
        json_value="$value"
    else
        json_value="$(jq -Rn --arg v "$value" '$v')"
    fi

    local root merged payload
    root="$(_py_root)"
    merged="$(jq -nc --argjson base "$root" --arg k "$key" --argjson v "$json_value" '$base + {($k): $v}')"
    payload="$(jq -nc --argjson m "$merged" '{path: "python", value: $m}')"
    _py_patch "$payload"
}

update_settings_bulk() {
    local json_obj="$1"

    local root merged payload
    root="$(_py_root)"
    merged="$(jq -nc --argjson base "$root" --argjson patch "$json_obj" '$base + $patch')"
    payload="$(jq -nc --argjson m "$merged" '{path: "python", value: $m}')"
    _py_patch "$payload"
}
