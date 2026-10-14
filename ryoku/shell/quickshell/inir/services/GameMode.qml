pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import inir
import inir.modules.common
import inir.modules.common.functions
import inir.services

/**
 * GameMode service - detects fullscreen windows and disables effects for performance.
 *
 * Two activation modes:
 * - Manual: user toggle via toggle()/activate()/deactivate(). Persists to file.
 * - Auto-detect: activates when focused window is fullscreen, deactivates
 *   immediately when leaving fullscreen. Applies the same performance
 *   optimizations as manual mode (no panel/background hiding).
 */
Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    // Public API
    // Visible fullscreen state is maintained reactively by WorkspaceService.
    // Keep one automatic source of truth so a cached state cannot outlive the
    // provider's fullscreen-exit frame.
    readonly property bool _reactiveAutoActive: autoDetect && hasVisibleFullscreenWindow
    readonly property bool active: _manualActive || _reactiveAutoActive
    readonly property bool autoDetect: Config.options?.gameMode?.autoDetect ?? true
    property bool manuallyActivated: _manualActive
    readonly property bool autoActivated: !_manualActive && _reactiveAutoActive

    // Surface mapping caused native crash loops; GameMode only suppresses work.

    // True if ANY window in ANY workspace is fullscreen (for toast suppression)
    readonly property bool hasAnyFullscreenWindow: checkAnyFullscreenWindow()

    // True when a fullscreen window owns any active output.
    readonly property bool hasVisibleFullscreenWindow: CompositorService.hasVisibleFullscreenWindow()


    // Internal state
    property bool _manualActive: false
    property bool _initialized: false

    // Config-driven behavior (reactive bindings - re-evaluated when Config changes)
    readonly property bool disableAnimations: Config.options?.gameMode?.disableAnimations ?? true
    readonly property bool disableEffects: Config.options?.gameMode?.disableEffects ?? true
    readonly property bool disableVisualizers: Config.options?.gameMode?.disableVisualizers ?? true
    readonly property bool disableReloadToasts: Config.options?.gameMode?.disableReloadToasts ?? true
    readonly property bool minimalMode: Config.options?.gameMode?.minimalMode ?? true
    readonly property bool visualizersSuppressed: active && disableVisualizers
    // Compositor-wide animation control belongs to the window manager's own
    // game mode, not the frame: the frame suppresses its effects and motion
    // through Appearance while this is active.

    readonly property bool suppressNotifications: Config.options?.gameMode?.suppressNotifications ?? true

    // discover-overlay (a Discord overlay) closes while you play and comes back after, wherever it is
    // installed: as a systemd user unit or a plain process. Where it is absent (Void ships no package) the
    // option hides and nothing runs.
    readonly property bool disableDiscoverOverlay: Config.options?.gameMode?.disableDiscoverOverlay ?? true
    property bool discoverOverlayInstalled: false
    property string _discoverOverlayStoppedAs: ""   // "unit", "process", or "" when we stopped nothing

    Process {
        id: discoverOverlayProbe
        running: true
        command: ["/bin/sh", "-c", "command -v discover-overlay >/dev/null"]
        onExited: (exitCode, exitStatus) => root.discoverOverlayInstalled = exitCode === 0
    }

    // The pattern is anchored to the program itself (`discover-overlay …` or `python3 …/discover-overlay`), so it
    // never matches a shell, editor or grep whose command line merely mentions the name, this script included.
    Process {
        id: discoverOverlayStopProc
        command: ["/bin/sh", "-c",
            "p='^([^ ]*/)?(python[0-9.]* +)?([^ ]*/)?discover-overlay( |$)'; pgrep -f \"$p\" >/dev/null || exit 1; " +
            "u=discover-overlay.service; " +
            "if [ -d /run/systemd/system ] && systemctl --user is-active --quiet \"$u\"; then " +
            "systemctl --user stop \"$u\" && echo unit; exit; fi; " +
            "pkill -f \"$p\" && echo process"]
        stdout: StdioCollector {
            id: discoverOverlayStopOut
            onStreamFinished: root._discoverOverlayStoppedAs = (discoverOverlayStopOut.text ?? "").trim()
        }
    }

    Timer {
        id: discoverOverlayDebounce
        interval: 800
        onTriggered: {
            const shouldStop = root.active && root.disableDiscoverOverlay && root.discoverOverlayInstalled
            if (shouldStop && root._discoverOverlayStoppedAs === "") {
                discoverOverlayStopProc.running = true
            } else if (!shouldStop && root._discoverOverlayStoppedAs === "unit") {
                Quickshell.execDetached(["systemctl", "--user", "start", "discover-overlay.service"])
                root._discoverOverlayStoppedAs = ""
            } else if (!shouldStop && root._discoverOverlayStoppedAs === "process") {
                ShellExec.execDetachedArgs(["discover-overlay"], "Discover overlay")
                root._discoverOverlayStoppedAs = ""
            }
        }
    }

    onDisableDiscoverOverlayChanged: discoverOverlayDebounce.restart()

    // State file path
    readonly property string _stateFile: Directories.stateUserPath + "/gamemode_active"

    // IPC handler for external control
    IpcHandler {
        target: "gamemode"
        function toggle(): void { root.toggle() }
        function activate(): void { root.activate() }
        function deactivate(): void { root.deactivate() }
        function status(): string {
            const state = root.active ? "active" : "inactive";
            const detail = root._manualActive ? "manual" : root.autoActivated ? "auto" : "off";
            return state + " (" + detail + ")";
        }
    }

    function toggle() {
        _manualActive = !_manualActive
        _saveState()
        root._log("[GameMode] Toggled manually:", _manualActive)
    }

    function activate() {
        _manualActive = true
        _saveState()
        root._log("[GameMode] Activated manually")
    }

    function deactivate() {
        _manualActive = false
        _saveState()
        root._log("[GameMode] Deactivated manually")
    }

    function _saveState() {
        saveProcess.running = true
    }

    function _loadState() {
        stateReader.reload()
    }

    function isWindowFullscreen(window): bool {
        return CompositorService.isWindowFullscreen(window)
    }

    // True when a fullscreen window covers the given output. An empty name
    // asks whether any active output is covered.
    function hasFullscreenOnOutput(outputName: string): bool {
        const scopedOutput = String(outputName ?? "")
        return scopedOutput.length > 0
            ? CompositorService.hasFullscreenOnOutput(scopedOutput)
            : CompositorService.hasVisibleFullscreenWindow()
    }

    // True if any workspace, active or not, contains a fullscreen window.
    function checkAnyFullscreenWindow(): bool {
        return (WorkspaceService.allWorkspaces ?? []).some(workspace => workspace.has_fullscreen === true)
    }

    // State persistence - read
    FileView {
        id: stateReader
        path: root._stateFile
        // No state file on first run is the normal case, not an error.
        printErrors: false

        onLoaded: {
            const content = stateReader.text()
            root._manualActive = (content.trim() === "1")
            root._initialized = true
            root._log("[GameMode] Initialized, manual:", root._manualActive)
        }

        onLoadFailed: (error) => {
            // File doesn't exist yet, that's fine
            root._manualActive = false
            root._initialized = true
            root._log("[GameMode] Initialized (no saved state)")
        }
    }

    // State persistence - write via process
    Process {
        id: saveProcess
        command: [
            "/usr/bin/bash",
            "-c",
            "mkdir -p '" + Directories.stateUserPath + "'\n" +
            "echo " + (root._manualActive ? "1" : "0") + " > " + root._stateFile
        ]
        onExited: root._log("[GameMode] State saved:", root._manualActive)
    }

    // Initial setup
    Component.onCompleted: {
        root._log("[GameMode] Service starting...")
        Quickshell.execDetached(["/usr/bin/mkdir", "-p", Directories.stateUserPath])
        initTimer.restart()
    }

    Timer {
        id: initTimer
        interval: 200
        onTriggered: root._loadState()
    }


    onActiveChanged: {
        root._log("[GameMode] Active:", active, "(manual:", _manualActive, "auto:", _reactiveAutoActive, ")")
        // Animation control lives at the window-manager layer.
        if (root.disableDiscoverOverlay && root.discoverOverlayInstalled) {
            discoverOverlayDebounce.restart()
        }
    }
}
