import QtQuick
import inir
import inir.services
import inir.modules.common
import inir.modules.iris.closeConfirm
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Confirms a window close before it happens, when `closeConfirm.enabled` is set.
// The trigger arrives over the `closeConfirm` IPC target — the compositor's
// close-window keybind calls it while the iRiS bar style is active — and the
// window is closed through the window-manager seam, never a compositor command.
Scope {
    id: root

    // Window captured at the moment of trigger (prevents a race with focus).
    property var targetWindow: null
    property var dialogScreen: null
    property bool dialogVisible: false

    // Debounce to prevent a double-trigger.
    property bool _busy: false
    Timer {
        id: debounce
        interval: 200
        onTriggered: root._busy = false
    }

    readonly property bool confirmEnabled: Config.options?.closeConfirm?.enabled ?? false

    function processWindow(win): void {
        if (root.confirmEnabled) {
            root.targetWindow = win
            root.dialogScreen = GlobalStates.focusedScreen
            root.dialogVisible = true
        } else {
            root.closeWindowFast(win)
        }
    }

    function _acceptTrigger(): bool {
        if (root._busy)
            return false
        root._busy = true
        debounce.restart()
        return true
    }

    IpcHandler {
        target: "closeConfirm"

        function trigger(): void {
            if (!root._acceptTrigger())
                return
            const win = CompositorService.activeWindow
            if (win?.id)
                root.processWindow(win)
        }

        function triggerWindow(windowId: int, appId: string): void {
            if (windowId <= 0 || !root._acceptTrigger())
                return
            root.processWindow({
                id: windowId,
                app_id: appId
            })
        }

        function close(): void {
            root.dialogVisible = false
            root.targetWindow = null
            root.dialogScreen = null
        }
    }

    function closeWindowFast(win): void {
        if (!win?.id)
            return
        const appId = String(win?.app_id ?? "").toLowerCase()
        if (appId === "spotify") {
            MinimizedWindows.minimize(win.id)
            return
        }
        CompositorService.closeWindow(win.id)
    }

    function confirmClose(): void {
        if (targetWindow)
            closeWindowFast(targetWindow)
        dialogVisible = false
        targetWindow = null
        dialogScreen = null
    }

    function cancel(): void {
        dialogVisible = false
        targetWindow = null
        dialogScreen = null
    }

    Loader {
        active: root.dialogVisible

        sourceComponent: PanelWindow {
            screen: root.dialogScreen ?? GlobalStates.focusedScreen

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            color: "transparent"
            WlrLayershell.namespace: "quickshell:closeConfirm"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            Loader {
                id: contentLoader
                anchors.fill: parent
                focus: true
                // The content declares targetWindow as required, so it must be
                // built from an inline Component: a source URL cannot initialize
                // a required property and would fail to Loader.Error, leaving this
                // keyboard-exclusive fullscreen window with no way out.
                sourceComponent: irisContent
                onLoaded: if (item) item.forceActiveFocus()

                Component {
                    id: irisContent
                    IrisCloseConfirmContent {
                        targetWindow: root.targetWindow
                        onConfirm: root.confirmClose()
                        onCancel: root.cancel()
                    }
                }
            }
        }
    }
}
