import QtQuick
import Quickshell
import Quickshell.Io

// The Picker stays built while closed, so opening only maps it. A nonzero
// performance.releaseAfterHideSeconds ends the process once it has been closed
// that long; the daemon starts a fresh one on the next open.
Scope {
    id: shell

    readonly property bool _startVisible: Quickshell.env("RYOGAMI_START_VISIBLE") === "1"
    readonly property var _startSettings: Quickshell.env("RYOGAMI_START_SETTINGS")
    property bool _startupPending: false

    property SettingValue _releaseSetting: SettingValue { key: "performance.releaseAfterHideSeconds" }
    readonly property int _releaseSecs: {
        var v = Number(shell._releaseSetting.value)
        return (isNaN(v) || v <= 0) ? 0 : Math.round(v)
    }

    Picker { id: picker }

    function show() { picker.show() }
    function hide() { picker.hide() }
    function toggle() { picker.toggle() }
    function settings(tab) { picker.openSettings(tab) }

    function completeStartup() {
        shell._startupPending = false
        if (typeof shell._startSettings === "string")
            shell.settings(shell._startSettings)
        else if (shell._startVisible)
            shell.show()
    }

    Timer {
        id: releaseTimer
        interval: Math.max(shell._releaseSecs, 1) * 1000
        onTriggered: if (shell._releaseSecs > 0 && !picker.shown) Qt.quit()
    }

    Connections {
        target: picker
        function onShownChanged() {
            if (picker.shown) {
                releaseTimer.stop()
            } else {
                if (shell._releaseSecs > 0)
                    releaseTimer.restart()
                // The daemon swaps in a fresh process while hidden when the GPU preference changed.
                Daemon.call("picker.hidden")
            }
        }
    }

    Connections {
        target: Daemon
        function onEvent(name, data) {
            if (name === "ryogami.wall.toggle")
                shell.toggle()
            else if (name === "ryogami.wall.settings")
                shell.settings(data && data.tab ? data.tab : "")
        }
        function onReconnected() {
            if (shell._startupPending)
                shell.completeStartup()
        }
    }

    IpcHandler {
        target: "ryogami"
        function toggle(): void { shell.toggle() }
        function show(): void { shell.show() }
        function hide(): void { shell.hide() }
        function settings(tab: string): void { shell.settings(tab) }
    }

    Component.onCompleted: {
        if (typeof shell._startSettings !== "string" && !shell._startVisible)
            return
        if (Daemon.connected)
            shell.completeStartup()
        else
            shell._startupPending = true
    }
}
