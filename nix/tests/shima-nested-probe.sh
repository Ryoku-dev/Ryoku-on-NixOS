#!/usr/bin/env bash
exec > /mnt/probe.log 2>&1
set -eu
ulimit -c 0
export PATH="$SHIMA_TEST_DAEMON/bin:$SHIMA_TEST_PACKAGE/bin:$PATH"
unset RYOKU_SHIMA_ENABLE
export RYOKU_SHELL_DIR="$SHIMA_TEST_NATIVE_ROOT"
mkdir -p "$XDG_CONFIG_HOME/ryoku"
printf '{"barStyle":"iris"}\n' > "$XDG_CONFIG_HOME/ryoku/shell.json"
ryogami daemon > /mnt/ryogami.log 2>&1 &
wallOwner=$!
for attempt in $(seq 1 100); do
    test -S "$XDG_RUNTIME_DIR/ryogami.sock" && break
    sleep 0.1
done
ryogami wallpaper set /mnt/wallpaper.svg
ryoku-shell daemon > /mnt/daemon.log 2>&1 &
owner=$!
trap 'kill "$owner" "$wallOwner" 2>/dev/null || true; niri msg action quit --skip-confirmation >/dev/null 2>&1 || true' EXIT

python3 - <<'PY'
import json,os,time
from pathlib import Path
runtime=Path(os.environ["XDG_RUNTIME_DIR"])
for _ in range(200):
    ready=[p for p in runtime.glob("ryoku-shima-ready-*") if p.read_text().strip()]
    if ready:break
    time.sleep(.1)
else:raise SystemExit("Shima startup did not acknowledge readiness")
PY

if [[ "${SHIMA_STARTUP_ONLY:-0}" == 1 ]]; then
    sleep 12
    if [[ "${SHIMA_VERIFY_DESKTOP:-0}" == 1 ]]; then
        ryoku-shima ipc call background legibilityState > /mnt/desktop-widget-state.json
        python3 - <<'PYDESKTOP'
import json
from pathlib import Path
state = json.loads(Path("/mnt/desktop-widget-state.json").read_text())
assert isinstance(state, list), "Shima desktop widget controller unavailable"
PYDESKTOP
    fi
    python3 - <<'PYSHIMA'
import json, os
from pathlib import Path
runtime = Path(os.environ["XDG_RUNTIME_DIR"])
ready = [p for p in runtime.glob("ryoku-shima-ready-*") if p.read_text().strip()]
assert len(ready) == 1, "Shima did not remain ready after startup"
pid = int(ready[0].read_text().strip())
assert Path(f"/proc/{pid}").exists(), "Shima process exited after readiness"
Path("/mnt/result.json").write_text(json.dumps({"passed": True, "pid": pid, "mode": "startup-only"}))
PYSHIMA
    ryoku-shell quit || true
    wait "$owner" || true
    niri msg action quit --skip-confirmation || true
    trap - EXIT
    exit 0
fi

if [[ "${SHIMA_TEST_WIDGETS:-0}" == 1 ]]; then
    python3 /mnt/widget-probe.py
fi

for family in iris ii waffle; do
    ryoku-shima ipc call panelFamily set "$family" >> /mnt/ipc.log 2>&1
    SHIMA_EXPECT_FAMILY="$family" python3 - <<'PY'
import json,os,time
from pathlib import Path
path=Path(os.environ["XDG_CONFIG_HOME"])/"ryoku/shima/config.json"
for _ in range(200):
    if path.exists() and json.loads(path.read_text()).get("panelFamily")==os.environ["SHIMA_EXPECT_FAMILY"]:
        break
    time.sleep(.1)
else:raise SystemExit("Panel family was not persisted")
time.sleep(5)
PY
    gdbus call --session --dest org.freedesktop.Notifications --object-path /org/freedesktop/Notifications --method org.freedesktop.Notifications.GetServerInformation >> /mnt/notification-server.log
    notify-send "Shima $family" "Isolated notification check"
    gdbus call --session --dest org.kde.StatusNotifierWatcher --object-path /StatusNotifierWatcher --method org.freedesktop.DBus.Properties.Get org.kde.StatusNotifierWatcher IsStatusNotifierHostRegistered >> /mnt/tray-host.log
    niri msg action screenshot-screen --path "/mnt/$family.png" >> /mnt/screenshot.log 2>&1
done

ryoku-shima ipc call shell openSurface "" settings >> /mnt/ipc.log 2>&1
sleep 3
niri msg action screenshot-screen --path /mnt/settings.png >> /mnt/screenshot.log 2>&1
ryoku-shell barstyle python >> /mnt/ipc.log 2>&1
sleep 5
ryoku-shell barstyle iris >> /mnt/ipc.log 2>&1
sleep 6

python3 - <<'PY'
import os,signal,time
from pathlib import Path
runtime=Path(os.environ["XDG_RUNTIME_DIR"])
for _ in range(250):
    ready=[p for p in runtime.glob("ryoku-shima-ready-*") if p.read_text().strip()]
    if len(ready)==1:
        break
    time.sleep(.1)
else:
    raise SystemExit("Shima re-entry did not acknowledge readiness")
pid=int(ready[0].read_text().strip())
os.kill(pid,signal.SIGKILL)
PY

sleep 6
python3 - <<'PY'
import json,os
from pathlib import Path
path=Path(os.environ["XDG_CONFIG_HOME"])/"ryoku/shell.json"
assert json.loads(path.read_text()).get("barStyle")=="python","Crash fallback did not restore Python"
PY
ryoku-shell quit >> /mnt/ipc.log 2>&1
wait "$owner"
kill "$wallOwner"
wait "$wallOwner" || true
sleep 1
python3 - <<'PY'
import json
from pathlib import Path
remaining=[]
for path in Path("/proc").glob("[0-9]*/cmdline"):
    try:argv=path.read_bytes().split(b"\0")
    except OSError:continue
    exe=Path(argv[0].decode(errors="replace")).name.lstrip(".").removesuffix("-wrapped")
    if exe in ("qs","quickshell") and b"ipc" not in argv:
        remaining.append(path.parent.name)
assert not remaining,remaining
Path("/mnt/result.json").write_text(json.dumps({"passed":True,"families":["iris","ii","waffle"],"switchAway":"python","crashFallback":"python","remainingQuickshellProcesses":remaining}))
PY
niri msg action quit --skip-confirmation || true
trap - EXIT
