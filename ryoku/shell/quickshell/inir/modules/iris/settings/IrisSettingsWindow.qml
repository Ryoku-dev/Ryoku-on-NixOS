pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import inir
import inir.services
import inir.modules.iris.style
import inir.modules.iris.field as Field

FloatingWindow {
    id: root
    title: Translation.tr("Shima Settings")
    visible: GlobalStates.settingsOverlayOpen
    color: body.frame.material === "compositor" ? "transparent" : IrisStyle.surface
    implicitWidth: Math.round(1180 * IrisStyle.density)
    implicitHeight: Math.round(820 * IrisStyle.density)
    minimumSize: Qt.size(Math.round(560 * IrisStyle.density), Math.round(420 * IrisStyle.density))
    onClosed: GlobalStates.settingsOverlayOpen = false

    readonly property var settingsWindow: {
        const list = WorkspaceService.windows ?? []
        return list.find(window => window.title === root.title) ?? null
    }

    Binding {
        target: GlobalStates
        property: "settingsWindowBehind"
        value: root.visible && root.settingsWindow !== null && !root.settingsWindow.is_active
    }

    // IPC opens have no compositor activation token, so ask the neutral window-manager seam once the window appears.
    property bool focusedOnce: false
    onSettingsWindowChanged: if (root.settingsWindow && !root.focusedOnce) {
        root.focusedOnce = true
        WorkspaceService.focusWindow(root.settingsWindow.id)
    }
    onVisibleChanged: if (!root.visible) root.focusedOnce = false
    Component.onDestruction: GlobalStates.settingsWindowBehind = false

    Connections {
        target: GlobalStates
        function onSettingsRaiseRequestChanged(): void {
            if (root.settingsWindow) WorkspaceService.focusWindow(root.settingsWindow.id)
        }
    }

    Field.IrisBlurRegion {
        window: root
        shapes: body.frame.blurShapes
        windowWidth: root.width
        windowHeight: root.height
    }

    IrisSettings {
        id: body
        anchors.fill: parent
        windowed: true
    }
}
