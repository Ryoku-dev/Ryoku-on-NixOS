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
replace("services/GlobalActions.qml",
        '''            id: "open-task-manager",
            name: Translation.tr("Task Manager"),
            description: Translation.tr("Open system monitor"),
            icon: "monitoring",
            category: "system",
            keywords: ["task", "process", "monitor", "cpu", "ram", "htop"],
            execute: () => {
                AppLauncher.launch("taskManager")
            }
        },
    ]

    // APPEARANCE''',
        '''            id: "open-task-manager",
            name: Translation.tr("Task Manager"),
            description: Translation.tr("Open system monitor"),
            icon: "monitoring",
            category: "system",
            keywords: ["task", "process", "monitor", "cpu", "ram", "htop"],
            execute: () => {
                AppLauncher.launch("taskManager")
            }
        },
        {
            id: "open-ryoku-hub",
            name: Translation.tr("Ryoku Hub"),
            description: Translation.tr("Open Ryoku's system and desktop settings"),
            icon: "dashboard_customize",
            category: "system",
            keywords: ["ryoku", "hub", "system", "settings", "desktop"],
            execute: () => { Quickshell.execDetached(["ryoku-shell", "hub", "open"]) }
        },
    ]

    // APPEARANCE''')
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

# Reuse upstream family-aware IPC implementations for Ryoku's shortcut bus.
for target in ["overview", "clipboard", "settings", "sidebarRight", "sidebarLeft", "controlPanel", "dashboard", "wactionCenter", "wnotificationCenter", "session", "cheatsheet", "bar"]:
    replace("shell.qml", f'target: "{target}"', f'id: ryoku{target[0].upper() + target[1:]}; target: "{target}"')

(root / "services/RyokuHost.qml").write_text(Path(sys.argv[3]).read_text())
with (root / "services/qmldir").open("a") as out:
    out.write("\nsingleton RyokuHost 1.0 RyokuHost.qml\n")
replace("services/Wallpapers.qml", 'function currentMainWallpaperPath(monitorName = ""): string {',
        'function currentMainWallpaperPath(monitorName = ""): string {\n        if (RyokuHost.ready) return RyokuHost.pathFor(monitorName)')
replace("modules/background/Background.qml", 'const configuredPath = (_multiMonEnabled && wallpaperData.path)',
        'const configuredPath = RyokuHost.ready ? RyokuHost.pathFor(monitorName) : (_multiMonEnabled && wallpaperData.path)')
# External Ryogami video keeps its background surface. The family backgrounds
# retain widgets, menus and clocks while suppressing their duplicate painter.
replace("modules/iris/background/IrisBackground.qml", 'id: canvas',
        'id: canvas\n            visible: !RyokuHost.liveFor(panel.monitorName)')
replace("modules/iris/background/IrisBackground.qml",
        'readonly property bool externalWallpaper: AwwwBackend.supportsVisibleMainWallpaper(',
        'readonly property bool externalWallpaper: RyokuHost.liveFor(panel.monitorName) || AwwwBackend.supportsVisibleMainWallpaper(')
replace("modules/background/Background.qml", 'readonly property bool externalMainWallpaperActive: bgRoot.externalMainWallpaperEligible',
        'readonly property bool externalMainWallpaperActive: RyokuHost.liveFor(bgRoot.monitorName) || bgRoot.externalMainWallpaperEligible')
replace("modules/waffle/background/WaffleBackground.qml", 'readonly property bool externalMainWallpaperActive: panelRoot.externalMainWallpaperEligible',
        'readonly property bool externalMainWallpaperActive: RyokuHost.liveFor(panelRoot._monitorName) || panelRoot.externalMainWallpaperEligible')
replace("services/Wallpapers.qml", 'updatePerMonitorConfig(normalizedPath, monitorName)',
        'updatePerMonitorConfig(normalizedPath, monitorName)\n            Quickshell.execDetached(["ryoku-shima-wallpaper", "--screen", monitorName, normalizedPath])')
replace("modules/common/functions/Session.qml",
        'Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "lock", "activate"]);',
        'Quickshell.execDetached(["ryoku-shell", "lock"]);')
replace("modules/common/functions/Session.qml", '_suspendTimer.restart()', 'Quickshell.execDetached(["ryoku-shell", "suspend"])')
# All CLI lock entry points use Ryoku's session-scoped proof/lock owner.
replace("scripts/inir", 'case "${1:-}" in', 'case "${1:-}" in\n    lock) exec ryoku-shell lock ;;')

(root / "services/PolkitServiceImpl.qml").write_text(Path(sys.argv[4]).read_text())
replace("services/PolkitService.qml", "Component.onCompleted: {", "Component.onCompleted: {\n        root._loadImpl(); return;")
for name, scope in [("modules/background/Background.qml", "bgRoot.monitorName"), ("modules/waffle/background/WaffleBackground.qml", "panelRoot._monitorName")]:
    replace(name, "id: wallpaperContainer", "id: wallpaperContainer\n                visible: !RyokuHost.liveFor(" + scope + ")")

(root / "modules/lock/Lock.qml").write_text(Path(sys.argv[5]).read_text())
