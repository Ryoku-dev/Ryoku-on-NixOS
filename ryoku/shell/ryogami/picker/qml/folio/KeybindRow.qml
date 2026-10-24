import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var control: ({})
    property var state
    property var options
    property var host
    property real reveal: 1

    readonly property string rk: row.control.key ? row.control.key : ""
    readonly property bool atDefault: sv.isDefault
    readonly property bool _capturing: row.host && row.host.capturingKey !== undefined && row.host.capturingKey === row.rk

    implicitHeight: line.height

    SettingValue { id: sv; key: row.rk }

    Item {
        id: line
        width: row.width
        height: Math.max(title.implicitHeight, bind.height)

        Text {
            id: title
            anchors.left: parent.left
            anchors.right: rightGroup.left
            anchors.rightMargin: 10 * Theme.scale
            anchors.verticalCenter: parent.verticalCenter
            text: row.control.label ? row.control.label : ""
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontField
            color: Theme.withAlpha(Theme.surfaceText, row.enabled ? row.reveal : 0.4 * row.reveal)
            elide: Text.ElideRight
        }

        Row {
            id: rightGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * Theme.scale

            ResetChip {
                anchors.verticalCenter: parent.verticalCenter
                visible: !row.atDefault && row.enabled
                onTriggered: sv.reset()
            }
            KeybindButton {
                id: bind
                anchors.verticalCenter: parent.verticalCenter
                enabled: row.enabled
                minWidth: 132
                maxWidth: 210
                binding: (sv.value === undefined || sv.value === null) ? "" : String(sv.value)
                capturing: row._capturing
                onCaptureRequested: if (row.host && row.host.captureKeybind) row.host.captureKeybind(row.control)
            }
        }
    }
}
