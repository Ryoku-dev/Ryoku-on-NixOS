#!/usr/bin/env bash
set -euo pipefail

root=${RYOKU_PATH:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
spawn="$root/ryoku/ui/Singletons/Spawn.qml"
app="$root/ryoku/shell/quickshell/shell/services/AppLaunch.qml"
module="$root/nix/modules/ryoku.nix"

grep -Fq 'Quickshell.env("RYOKU_SYSTEMD_RUN")' "$spawn"
grep -Fq '"--scope"' "$spawn"
grep -Fq '"--slice=app.slice"' "$spawn"
grep -Fq 'function runApp(command' "$spawn"
[ "$(grep -Fc 'Spawn.runApp(' "$app")" -eq 2 ]

python3 - "$module" <<'EOFTEST'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
start = text.index('systemd.user.services.ryoku-shell = {')
block = text[start:]
if 'KillMode = "control-group";' not in block:
    raise SystemExit('ryoku-shell.service must use KillMode=control-group')
EOFTEST

printf 'shell-app-scope: PASS\n'
