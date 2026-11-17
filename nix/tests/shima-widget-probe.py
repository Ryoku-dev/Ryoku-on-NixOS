#!/usr/bin/env python3
"""Exercise the shipped upstream widget catalogue inside the nested test session."""
import json
import os
from pathlib import Path
import re
import subprocess
import time

runtime = Path(os.environ["SHIMA_TEST_PACKAGE"])/"share/quickshell/inir"
source = (runtime/"modules/background/Background.qml").read_text()
known = re.search(r"const knownWidgets = (\[[\s\S]*?\]);", source)
widgets = json.loads(known.group(1))
faces = set(re.findall(r'key: "([^"]+)"', (runtime/"modules/iris/widgets/IrisFaceData.qml").read_text().split("readonly property var otherEntries")[0]))

def ipc(target, method, *args):
    result = subprocess.run(["ryoku-shima", "ipc", "call", target, method, *map(str,args)],
                            capture_output=True, text=True, timeout=10)
    if result.returncode:
        raise RuntimeError(method+": "+result.stdout+result.stderr)
    return result.stdout.strip()

def call(method, *args):
    return ipc("background", method, *args)

def until(check, message, seconds=15):
    deadline = time.monotonic()+seconds
    while time.monotonic()<deadline:
        value = check()
        if value:
            return value
        time.sleep(.15)
    raise RuntimeError(message)

out = Path("/mnt/widgets")
out.mkdir(exist_ok=True)
for widget in widgets:
    call("setWidgetEnabled", widget, "false")
report = []
for widget in widgets:
    print("Testing widget:",widget,flush=True)
    call("setWidgetEnabled",widget,"true")
    availability = call("focusWidget",widget,"false")
    if availability.startswith("widget unavailable:"):
        report.append(dict(widget=widget,skipped=availability))
        call("setWidgetEnabled",widget,"false")
        continue
    entry = until(lambda: next((row for row in json.loads(call("legibilityState")) if row["widget"]==widget),None),
                  "Widget failed to load: "+widget)
    if widget in faces:
        assert entry["face"], widget+" did not load its upstream iRiS face"
    image = out/(widget+".png")
    reply = call("widgetSnapshot",widget,str(image))
    until(lambda: image.exists() and image.stat().st_size>100, "Widget did not render: "+widget+" "+reply)
    selection = call("focusWidget",widget,"true")
    assert selection.endswith("::"+widget), selection
    pages = {}
    for page in ("widget","look","arrange"):
        value = json.loads(call("quickControlsPage",page))
        assert value["widget"].endswith("::"+widget), value
        pages[page] = value["page"]
    report.append(dict(widget=widget,irisFace=bool(entry["face"]),controls=pages,snapshot=image.name))
    call("setEditMode","false")
    call("setWidgetEnabled",widget,"false")
# Verify each stack member becomes visible and persisted before adding another.
# These are two upstream iRiS widget faces, without Notes' extra editing state.
def widget_ready(name):
    config_file = Path(os.environ["XDG_CONFIG_HOME"]) / "ryoku/shima/config.json"
    if not config_file.exists():
        return False
    try:
        settings = json.loads(config_file.read_text())
        enabled = settings.get("background", {}).get("widgets", {}).get(name, {}).get("enable")
        state = json.loads(call("legibilityState"))
        return enabled is True and any(row["widget"] == name for row in state)
    except (ValueError, OSError):
        return False

for widget in ("clock", "weather"):
    result = call("setWidgetEnabled", widget, "true")
    assert result == widget + " enabled", result
    until(lambda name=widget: widget_ready(name), "Stack member did not load: " + widget, 30)

stack = ipc("widgetStacks", "create", "clock+weather")
state = json.loads(ipc("widgetStacks", "status"))
assert next(row for row in state["stacks"] if row["id"] == stack)["members"] == ["clock", "weather"], state
assert ipc("widgetStacks", "rotate", stack, "off") == "rotation off"
assert ipc("widgetStacks", "page", stack, "weather") == "weather"
assert ipc("widgetStacks", "move", stack, "weather", -1) == "moved"
state = json.loads(ipc("widgetStacks", "status"))
assert next(row for row in state["stacks"] if row["id"] == stack)["members"] == ["weather", "clock"], state
assert ipc("widgetStacks", "dissolve", stack) == "dissolved"
call("setWidgetEnabled", "weather", "false")
# Leave one widget enabled and verify its persisted setting survives a shell reload.
call("setWidgetEnabled","clock","true")
config = Path(os.environ["XDG_CONFIG_HOME"])/"ryoku/shima/config.json"
until(lambda: json.loads(config.read_text()).get("background",{}).get("widgets",{}).get("clock",{}).get("enable") is True,
      "Widget setting was not persisted")
ready = list(Path(os.environ["XDG_RUNTIME_DIR"]).glob("ryoku-shima-ready-*"))
old = [p.read_text().strip() for p in ready]
subprocess.run(["ryoku-shell","reload"],check=True,capture_output=True,text=True)
until(lambda: [p for p in Path(os.environ["XDG_RUNTIME_DIR"]).glob("ryoku-shima-ready-*") if p.read_text().strip() and p.read_text().strip() not in old],
      "Widget reload did not become ready",30)
def clock_restored():
    result = subprocess.run(
        ["ryoku-shima", "ipc", "call", "background", "legibilityState"],
        capture_output=True, text=True, timeout=10,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return False
    try:
        return any(row["widget"] == "clock" for row in json.loads(result.stdout))
    except json.JSONDecodeError:
        return False

until(clock_restored, "Clock was not restored after reload", 45)
Path("/mnt/widget-result.json").write_text(json.dumps(dict(passed=True,widgets=report,persistence=True,stacks=True),indent=2))
print("PASS:",sum("snapshot" in row for row in report),"rendered widgets,",sum("skipped" in row for row in report),"hardware-dependent skip, quick controls, stacks and persisted reload",flush=True)
