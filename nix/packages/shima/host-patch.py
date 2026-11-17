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

# Upstream's packaged /usr/bin/ strip turns these executable tests into
# cwd-relative paths, so every launch skipped its transient scope and stayed in
# ryoku-shell.service, dying whenever that unit restarted.
replace("modules/common/functions/ShellExec.qml",
        'readonly property string systemdRunPath: "/usr/bin/systemd-run"',
        'readonly property string systemdRunPath: Quickshell.env("RYOKU_SYSTEMD_RUN") || "/usr/bin/systemd-run"')
replace("modules/common/functions/ShellExec.qml",
        '[ -x /usr/bin/systemctl ] && [ -x /usr/bin/timeout ]; then',
        'command -v systemctl >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then')
replace("modules/common/functions/ShellExec.qml",
        'if [ -x "$systemd_run" ] && [ "$systemd_user_manager_usable" = true ]; then',
        'if command -v "$systemd_run" >/dev/null 2>&1 && [ "$systemd_user_manager_usable" = true ]; then')
# Launches take the session PATH first; Shima's own CLI keeps its pinned qs.
replace("scripts/inir", 'qs_bin="/usr/bin/qs"', 'qs_bin="${RYOKU_SHIMA_QS:-/usr/bin/qs}"')

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


# Keep the desktop canvas and context menu available when a saved upstream
# enabledPanels list predates the full iNiR desktop integration.
replace("modules/iris/critical/ShellIrisCriticalPanels.qml",
        '''    CriticalPanelLoader {
        identifier: "irisBackground"
        extraCondition: !(Config.options?.iris?.modules?.desktopWidgets ?? true)
        component: IrisBackground {}
    }''',
        '''    LazyLoader {
        active: Config.ready && IrisGate.official
            && !(Config.options?.iris?.modules?.desktopWidgets ?? true)
        component: IrisBackground {}
    }''')
replace("modules/iris/ShellIrisPanelsImpl.qml",
        '''            && (Config.options?.enabledPanels ?? []).includes("irisBackground")
            && (Config.options?.iris?.modules?.desktopWidgets ?? true)''',
        '''            && (Config.options?.iris?.modules?.desktopWidgets ?? true)''')

# The existing iNiR menu remains intact. Native Ryoku controls are appended
# even when an older user menu selects only the original action IDs.
replace("modules/iris/background/IrisDesktopActions.qml",
        '''        return out
    }

    function run(''',
        '''        out.push({ type: "separator" })
        out.push({ id: "ryokuSubshells", text: Translation.tr("Switch Ryoku subshell"),
            iconName: "swap_horiz", tint: "teal",
            action: () => Quickshell.execDetached(["ryoku-shell", "hub", "open", "subshells"]) })
        out.push({ id: "ryokuBarStudio", text: Translation.tr("Ryoku Bar Studio"),
            iconName: "view_carousel", tint: "blue",
            action: () => Quickshell.execDetached(["ryoku-shell", "hub", "open", "bar-studio"]) })
        out.push({ id: "ryokuDesktop", text: Translation.tr("Ryoku desktop settings"),
            iconName: "desktop_windows", tint: "gray",
            action: () => Quickshell.execDetached(["ryoku-shell", "hub", "open", "desktop"]) })
        out.push({ id: "ryokuHub", text: Translation.tr("Ryoku Hub"),
            iconName: "dashboard_customize", tint: "gray",
            action: () => Quickshell.execDetached(["ryoku-shell", "hub", "open"]) })
        return out
    }

    function run(''')

replace("modules/iris/settings/IrisThemes.qml",
        '    readonly property var curated: [',
        '''    readonly property var curated: [
        { id: "ryoku", name: "Ryoku", author: "Ryoku", tags: ["paper", "ink", "system"],
            description: "Ryoku's paper-and-ink palette adapted to Shima's upstream iRiS renderer.",
            values: root.values({ "iris.appearance.scheme": "ink", "iris.appearance.preset": "crisp",
                "theme.surface": "black", "theme.fill": 105, "theme.lines": 120,
                "theme.rim": true, "theme.rimTint": "neutral", "theme.shadow": 35,
                "theme.glow": 0, "glass.mode": "off", "iris.appearance.aura": "off",
                "iris.appearance.accent": "wallpaper", "iris.appearance.highlight": "accent",
                "iris.appearance.morph": "glide",
                "iris.appearance.fontFamily": "Inter", "iris.appearance.titleFontFamily": "Inter Display",
                "iris.appearance.numbersFontFamily": "JetBrains Mono",
                "iris.bar.layout": "full", "iris.bar.composition": "unified",
                "iris.bar.notch": false, "iris.bar.height": 40,
                "iris.controlCenter.controls": "tiles", "iris.controlCenter.sliders": "neutral",
                "iris.widgets.design": "iris", "iris.widgets.material": "solid",
                "iris.widgets.radius": 12, "iris.widgets.tint": "system",
                "iris.dock.material": "solid", "iris.dock.notch": false,
                "iris.dock.magnification": false }) },''')


replace("modules/iris/frame/IrisFramePulse.qml",
        'active: root.active && (MprisController.activePlayer?.isPlaying ?? false)',
        'active: root.active')
replace("modules/iris/frame/IrisFrame.qml",
        '&& String(root.surround?.music ?? "widget") === "frame"',
        '&& ["frame", "both"].includes(String(root.surround?.music ?? "widget"))')
replace("modules/iris/settings/IrisOptions.qml",
        '{label:"The wave",value:"widget"},{label:"The frame",value:"frame"}',
        '{label:"The wave",value:"widget"},{label:"The frame",value:"frame"},{label:"Both",value:"both"}')
replace("modules/iris/settings/IrisOptions.qml",
        'visibleWhen: "iris.surround.music=frame"',
        'visibleWhen: "!iris.surround.music=widget"')
replace("modules/iris/settings/IrisOptions.qml",
        '{ section: "frameMusic", group: "Frame response", label: "Edges",',
        '{ section: "frameMusic", group: "Wave response", label: "Wave edges", description: "Choose the sides carrying the Organic Edge visualiser. Select Left and Right for dual vertical waves.", path: "background.edgeWidgets.organic.edges", kind: "pieces", fallback: [], visibleWhen: "!iris.surround.music=frame", choices: [{label:"Left",value:"left"},{label:"Right",value:"right"},{label:"Top",value:"top"},{label:"Bottom",value:"bottom"}], keywords: ["music", "edge", "visualizer", "cava"] },\n        { section: "frameMusic", group: "Frame response", label: "Edges",')


tokenSource = Path(sys.argv[6]).read_text()
tokenSource = tokenSource.replace(
    '(Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/ryoku/colors.json"',
    '(Quickshell.env("HOME") + "/.cache/ryoku/colors.json")')
(root / "services/RyokuTokens.qml").write_text(tokenSource)
with (root / "services/qmldir").open("a") as out:
    out.write("\nsingleton RyokuTokens 1.0 RyokuTokens.qml\n")

replace("modules/iris/settings/IrisOptions.qml",
        '    readonly property var studioRows: [',
        '''    readonly property var studioRows: [
        { target: "material", group: "Look", label: "Shima appearance", description: "Ryoku uses the system paper-and-ink palette, preserving Liquid Glass and your other selected themes.", path: "iris.appearance.frontend", kind: "choice", fallback: "inir", choices: [{label:"Ryoku",value:"ryoku"},{label:"Original iNiR",value:"inir"}], keywords: ["ryoku", "theme", "appearance", "liquid glass"] },''')
replace("modules/iris/settings/IrisThemes.qml",
        'readonly property var excludedPaths: ["iris.bar.position",',
        'readonly property var excludedPaths: ["iris.appearance.frontend", "iris.bar.position",')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property var appearance: root.options?.appearance ?? ({})',
        '''    readonly property var appearance: root.options?.appearance ?? ({})
    readonly property bool ryokuFrontend: String(root.appearance?.frontend ?? "inir") === "ryoku"''')

replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color canvas: Appearance.colors.colLayer0Base',
        '    readonly property color canvas: root.ryokuFrontend ? RyokuTokens.paper : Appearance.colors.colLayer0Base')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property string colourTheme: String(ThemeService.currentTheme ?? "auto")',
        '    readonly property string colourTheme: root.ryokuFrontend ? "auto" : String(ThemeService.currentTheme ?? "auto")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property string scheme: ["dark", "ink", "light"].includes(root.schemeChoice) ? root.schemeChoice',
        '    readonly property string scheme: root.ryokuFrontend ? (RyokuTokens.light ? "light" : "dark") : ["dark", "ink", "light"].includes(root.schemeChoice) ? root.schemeChoice')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property var defaultFaces: ({',
        '    readonly property var defaultFaces: root.ryokuFrontend ? ({\n        "iris.appearance.fontFamily": RyokuTokens.ui,\n        "iris.appearance.titleFontFamily": RyokuTokens.display,\n        "iris.appearance.numbersFontFamily": RyokuTokens.mono\n    }) : ({')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color surfaceOpaque: root.role("surface", "#000000")',
        '    readonly property color surfaceOpaque: root.ryokuFrontend ? RyokuTokens.paper : root.role("surface", "#000000")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color surfaceHighOpaque: root.role("surfaceHigh", "#1c1c1e")',
        '    readonly property color surfaceHighOpaque: root.ryokuFrontend ? RyokuTokens.paperLift : root.role("surfaceHigh", "#1c1c1e")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color surfaceHighestOpaque: root.role("surfaceHighest", "#2c2c2e")',
        '    readonly property color surfaceHighestOpaque: root.ryokuFrontend ? ColorUtils.mix(RyokuTokens.ink, RyokuTokens.paper, 0.08) : root.role("surfaceHighest", "#2c2c2e")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property real tintAmount: Math.max(0, Math.min(1, Number(root.appearance?.tint ?? 0) / 100))',
        '    readonly property real tintAmount: root.ryokuFrontend ? 0 : Math.max(0, Math.min(1, Number(root.appearance?.tint ?? 0) / 100))')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color text: root.role("text", "#f5f5f7")',
        '    readonly property color text: root.ryokuFrontend ? RyokuTokens.ink : root.role("text", "#f5f5f7")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color subtext: ColorUtils.applyAlpha(root.quietInk, root.inkLevel(Math.max(0.78, root.preset.textStrong - 0.02), 0.9))',
        '    readonly property color subtext: root.ryokuFrontend ? RyokuTokens.inkDim : ColorUtils.applyAlpha(root.quietInk, root.inkLevel(Math.max(0.78, root.preset.textStrong - 0.02), 0.9))')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color muted: ColorUtils.applyAlpha(root.quietInk, root.inkLevel(Math.max(0.64, root.preset.textSecondary + 0.04), 0.8))',
        '    readonly property color muted: root.ryokuFrontend ? RyokuTokens.inkMuted : ColorUtils.applyAlpha(root.quietInk, root.inkLevel(Math.max(0.64, root.preset.textSecondary + 0.04), 0.8))')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color accent: root.animeEnabled',
        '    readonly property color accent: root.ryokuFrontend ? RyokuTokens.ink : root.animeEnabled')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color inkOnAccent: root.animeEnabled ? root.onTintFor(root.accent) : root.role("onAccent", "#101318")',
        '    readonly property color inkOnAccent: root.ryokuFrontend ? RyokuTokens.paper : root.animeEnabled ? root.onTintFor(root.accent) : root.role("onAccent", "#101318")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color accentContainer: root.role("accentContainer", "#1f3a5f")',
        '    readonly property color accentContainer: root.ryokuFrontend ? RyokuTokens.bone : root.role("accentContainer", "#1f3a5f")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color inkOnAccentContainer: root.role("onAccentContainer", "#d6e3ff")',
        '    readonly property color inkOnAccentContainer: root.ryokuFrontend ? RyokuTokens.inkOnBone : root.role("onAccentContainer", "#d6e3ff")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color secondaryAccent: {',
        '    readonly property color secondaryAccent: root.ryokuFrontend ? RyokuTokens.inkDim : root.secondaryAccentOriginal\n    readonly property color secondaryAccentOriginal: {')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color hairline: root.glassy ?',
        '    readonly property color hairline: root.ryokuFrontend ? RyokuTokens.line : root.glassy ?')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color hairlineStrong: root.glassy ?',
        '    readonly property color hairlineStrong: root.ryokuFrontend ? RyokuTokens.lineStrong : root.glassy ?')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color selection: root.accentContainer',
        '    readonly property color selection: root.ryokuFrontend ? RyokuTokens.tint16 : root.accentContainer')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color border: ColorUtils.applyAlpha(root.text, Math.min(0.5, 0.14 * root.preset.fill * root.tweak("lines", 0, 2)))',
        '    readonly property color border: root.ryokuFrontend ? RyokuTokens.line : ColorUtils.applyAlpha(root.text, Math.min(0.5, 0.14 * root.preset.fill * root.tweak("lines", 0, 2)))')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color borderStrong: ColorUtils.applyAlpha(root.text, Math.min(0.6, 0.28 * root.preset.fill * root.tweak("lines", 0, 2)))',
        '    readonly property color borderStrong: root.ryokuFrontend ? RyokuTokens.lineStrong : ColorUtils.applyAlpha(root.text, Math.min(0.6, 0.28 * root.preset.fill * root.tweak("lines", 0, 2)))')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color onTint: "#ffffff"',
        '    readonly property color onTint: root.ryokuFrontend ? RyokuTokens.inkOnBone : Qt.color("#ffffff")')
replace("modules/iris/style/IrisStyle.qml",
        '    readonly property color inkOnPale: "#101318"',
        '    readonly property color inkOnPale: root.ryokuFrontend ? RyokuTokens.paper : Qt.color("#101318")')

replace("modules/iris/background/IrisDesktopActions.qml",
        '        out.push({ id: "ryokuBarStudio", text: Translation.tr("Ryoku Bar Studio"),',
        '''        out.push({ id: "shimaAppearance", text: Translation.tr("Shima appearance: Ryoku or iNiR"),
            iconName: "palette", tint: "gray",
            action: () => GlobalStates.openIrisCustomize("material") })
        out.push({ id: "shimaIris", text: Translation.tr("Shima panels: iRiS"),
            iconName: "visibility", tint: "gray",
            action: () => Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "panelFamily", "set", "iris"]) })
        out.push({ id: "shimaIi", text: Translation.tr("Shima panels: Material ii"),
            iconName: "dashboard", tint: "gray",
            action: () => Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "panelFamily", "set", "ii"]) })
        out.push({ id: "shimaWaffle", text: Translation.tr("Shima panels: Waffle"),
            iconName: "window", tint: "gray",
            action: () => Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "panelFamily", "set", "waffle"]) })
        out.push({ id: "ryokuBarStudio", text: Translation.tr("Ryoku Bar Studio"),''')

replace("modules/iris/frame/IrisFramePulse.qml",
        '    property real level: 0\n    property real phase: 0',
        '    property real level: 0\n    property real lowLevel: 0\n    property real midLevel: 0\n    property real highLevel: 0\n    property real phase: 0')
replace("modules/iris/frame/IrisFramePulse.qml",
        '    readonly property vector4d amplitudes: Qt.vector4d(\n        root.edges !== "horizontal" ? root.visibleLevel * root.reach : 0,\n        root.edges !== "sides" ? root.visibleLevel * root.reach : 0,\n        root.edges !== "horizontal" ? root.visibleLevel * root.reach : 0,\n        root.edges !== "sides" ? root.visibleLevel * root.reach : 0)',
        '    readonly property vector4d amplitudes: Qt.vector4d(\n        root.edges !== "horizontal" ? (root.lowLevel * 0.6 + root.midLevel * 0.4) * root.reach : 0,\n        root.edges !== "sides" ? (root.highLevel * 0.75 + root.midLevel * 0.25) * root.reach : 0,\n        root.edges !== "horizontal" ? (root.midLevel * 0.6 + root.highLevel * 0.4) * root.reach : 0,\n        root.edges !== "sides" ? (root.lowLevel * 0.7 + root.midLevel * 0.3) * root.reach : 0)')
replace("modules/iris/frame/IrisFramePulse.qml",
        '        if (!root.active) {\n            root.level = 0\n            root.phase = 0\n        }',
        '        if (!root.active) {\n            root.level = 0\n            root.lowLevel = 0\n            root.midLevel = 0\n            root.highLevel = 0\n            root.phase = 0\n        }')
replace("modules/iris/frame/IrisFramePulse.qml",
        '        running: root.active && (cava.held || root.level > 0.002)',
        '        running: root.active && (cava.audioSignalActive || root.level > 0.002)')
replace("modules/iris/frame/IrisFramePulse.qml",
        '            let bass = 0\n            const count = Math.min(4, points.length)\n            for (let i = 0; i < count; ++i) bass += Number(points[i] ?? 0)\n            bass = count > 0 ? Math.min(1, bass / count / Math.max(1, cava.normalizationCeiling)) : 0\n            bass = Math.min(1, Math.sqrt(bass) * root.sensitivity)\n            const step = Math.min(0.05, frameTime)\n            const rate = bass > root.level ? 18 : 3.2\n            root.level += (bass - root.level) * Math.min(1, rate * step)\n            if (root.level < 0.002 && !cava.held) root.level = 0',
        '            const step = Math.min(0.05, frameTime)\n            const ceiling = Math.max(1, cava.normalizationCeiling)\n            function band(start, end) {\n                if (!points.length) return 0\n                const from = Math.floor(points.length * start)\n                const to = Math.max(from + 1, Math.min(points.length, Math.ceil(points.length * end)))\n                let sum = 0\n                for (let i = from; i < to; ++i) sum += Math.max(0, Number(points[i] ?? 0))\n                return Math.min(1, Math.sqrt(Math.min(1, sum / (to - from) / ceiling)) * root.sensitivity)\n            }\n            function smooth(current, target) {\n                const rate = target > current ? 18 : 3.2\n                const result = current + (target - current) * Math.min(1, rate * step)\n                return result < 0.002 && !cava.audioSignalActive ? 0 : result\n            }\n            root.lowLevel = smooth(root.lowLevel, band(0, 0.25))\n            root.midLevel = smooth(root.midLevel, band(0.25, 0.68))\n            root.highLevel = smooth(root.highLevel, band(0.68, 1))\n            root.level = Math.max(root.lowLevel, root.midLevel, root.highLevel)')
(root / "modules/lock/Lock.qml").write_text(Path(sys.argv[5]).read_text())
