pragma ComponentBehavior: Bound

import QtQuick
import inir

Item {
    id: root

    visible: false
    width: 0
    height: 0

    required property var dialog
    required property string dialogKey
    property bool engaged: false

    function sync(): void {
        const next = Boolean(root.dialog?.showing ?? false)
        if (next === root.engaged) return
        root.engaged = next
        GlobalStates.setSettingsNativeDialogVisible(root.dialogKey, next)
    }

    Connections {
        target: root.dialog
        function onShowingChanged(): void { root.sync() }
    }

    Component.onCompleted: root.sync()
    Component.onDestruction: {
        if (root.engaged)
            GlobalStates.setSettingsNativeDialogVisible(root.dialogKey, false)
    }
}
