#!/usr/bin/env bash
set -euo pipefail

root=${RYOKU_PATH:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
spawn="$root/ryoku/ui/Singletons/Spawn.qml"
app="$root/ryoku/shell/quickshell/shell/services/AppLaunch.qml"
module="$root/nix/modules/ryoku.nix"

host_app="$root/ryoku/cli/internal/host/app.go"
# Modern upstream owns app scoping via ryoku-host app.
grep -Fq 'function runApp(argv, opts)' "$spawn"
grep -Fq 'const command = ["ryoku-host", "app"];' "$spawn"
grep -Fq 'spawn.run(command);' "$spawn"
grep -Fq 'func (a *App) App(args []string) int {' "$host_app"
grep -Fq '"--scope"' "$host_app"
grep -Fq '"--slice=app.slice"' "$host_app"
grep -Fq '"--collect"' "$host_app"
grep -Fq 'scrubAppEnvironment()' "$host_app"
count="$(grep -Fc 'Spawn.runApp(' "$app" || true)"
[ "$count" -eq 2 ]
grep -Fq 'Spawn.runApp(["gtk-launch", String(entry.id)], { label: entry.id });' "$app"
grep -Fq 'Spawn.runApp(command, {' "$app"
grep -Fq 'cwd: entry ? entry.workingDirectory' "$app"
grep -Fq 'label: entry ? entry.id' "$app"

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
