#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${INIR_VENV:-}" ]]; then
    _ii_venv="$(eval echo "$INIR_VENV")"
elif [[ -n "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}" ]]; then
    _ii_venv="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")"
else
    _ii_venv="$HOME/.local/state/quickshell/.venv"
fi
# shellcheck disable=SC1091  # the venv activate script is generated at runtime
source "$_ii_venv/bin/activate" 2>/dev/null || true
"$_ii_venv/bin/python3" "$SCRIPT_DIR/least_busy_region.py" "$@"
deactivate 2>/dev/null || true
