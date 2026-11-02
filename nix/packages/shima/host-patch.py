from pathlib import Path
import sys

root = Path(sys.argv[1])
def replace(name, old, new):
    p = root / name
    s = p.read_text()
    if old not in s:
        raise RuntimeError(f"upstream compatibility anchor changed: {name}: {old}")
    p.write_text(s.replace(old, new))

replace("modules/common/Directories.qml",
        'property string shellConfig: `${Directories.configPath}/illogical-impulse`',
        'property string shellConfig: Quickshell.env("RYOKU_SHIMA_CONFIG")')
replace("scripts/lib/config-path.sh", 'inir_config_dir() {',
        'inir_config_dir() {\n    if [[ -n "${RYOKU_SHIMA_CONFIG:-}" ]]; then printf "%s\\n" "$RYOKU_SHIMA_CONFIG"; return; fi')
for old, new in [
    ("FirstRunExperience.load();", ""),
    ("ConflictKiller.load();", ""),
    ("root._autostartService = Autostart", ""),
    ("root._niriAnimationPresetsService = NiriAnimationPresets", ""),
    ("property var _idleService: Idle", "property var _idleService"),
    ("property var _powerProfilePersistence: PowerProfilePersistence", "property var _powerProfilePersistence"),
]:
    replace("shell.qml", old, new)
replace("shell.qml", "    id: root", "    id: root\n" + Path(sys.argv[2]).read_text())
replace("services/AwwwBackend.qml",
        'readonly property bool enabled: (Config.options?.background?.backend?.provider ?? "awww") === provider',
        'readonly property bool enabled: false')
replace("services/Wallpapers.qml", 'readonly property bool awwwBackendEnabled: true',
        'readonly property bool awwwBackendEnabled: false')
(root / "scripts/colors/switchwall.sh").write_text(
    "#!/usr/bin/env bash\nexec ryoku-shima-wallpaper \"$@\"\n")
(root / "scripts/restart-shell.sh").write_text(
    "#!/usr/bin/env bash\nexec ryoku-shell reload\n")

for family, title in [("iris", "Iris"), ("ii", "Ii"), ("waffle", "Waffle")]:
    replace("shell.qml", f'source: "modules/{family}/critical/Shell{title}CriticalPanels.qml"',
            f'id: ryoku{title}Critical; source: "modules/{family}/critical/Shell{title}CriticalPanels.qml"')
    replace("shell.qml", f'source: "Shell{title}Panels.qml"',
            f'id: ryoku{title}Deferred; source: "Shell{title}Panels.qml"')
replace("services/ThemeService.qml",
        "readonly property bool defaultApplyExternal: !isStandaloneSettingsWindow",
        "readonly property bool defaultApplyExternal: false")

(root / "scripts/switch-family-restart.py").write_text(
    "#!/usr/bin/env python3\nimport os, sys\nos.execvp('ryoku-shell', ['ryoku-shell', 'shima-family'] + sys.argv[1:])\n")

replace("services/TrayService.qml",
        'command: ["/usr/bin/bash", "-lc", root._xembedStartScript]',
        'command: ["env", "QT_QPA_PLATFORM=xcb", "QT_NO_XDG_DESKTOP_PORTAL=1", "xembedsniproxy"]')
cli = root / "scripts/inir"
head, rest = cli.read_text().split("\n", 1)
cli.write_text(head + "\n" + "case \"${1:-}\" in\n    run|start|stop|service|install|uninstall|setup|update)\n        echo \"Shima lifecycle and packages are managed by Ryoku on NixOS.\" >&2\n        exit 2 ;;\n    restart|reload) exec ryoku-shell reload ;;\nesac\n" + rest)
