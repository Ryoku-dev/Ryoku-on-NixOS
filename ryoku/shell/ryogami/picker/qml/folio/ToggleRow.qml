import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var control: ({})
    property var state
    property var options
    property real reveal: 1
    property bool bound: true
    property string keyOverride: ""
    property var boundValue: undefined
    signal edited(var value)

    readonly property string rk: row.keyOverride !== "" ? row.keyOverride : (row.control.key ? row.control.key : "")
    readonly property var _val: row.bound ? sv.value : row.boundValue
    readonly property bool _on: _val === true || _val === "true" || _val === 1
    readonly property bool atDefault: row.bound ? sv.isDefault : true

    implicitHeight: col.implicitHeight
    function resetValue() { if (row.bound) sv.reset() }
    function _apply(v) { if (row.bound) sv.set(v); else row.edited(v) }

    SettingValue { id: sv; key: row.bound ? row.rk : "" }

    Column {
        id: col
        width: row.width
        spacing: 3 * Theme.scale

        Item {
            width: parent.width
            height: Math.max(title.implicitHeight, toggle.height)

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
                wrapMode: Text.WordWrap
            }

            Row {
                id: rightGroup
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * Theme.scale

                ResetChip {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.bound && !row.atDefault && row.enabled
                    onTriggered: row.resetValue()
                }
                Switch {
                    id: toggle
                    anchors.verticalCenter: parent.verticalCenter
                    checked: row._on
                    enabled: row.enabled
                    onToggled: (v) => row._apply(v)
                }
            }
        }

        Text {
            width: parent.width
            visible: !!row.control.help && row.control.help.length > 0
            text: row.control.help ? row.control.help : ""
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBase
            color: Theme.withAlpha(Theme.surfaceText, 0.56 * row.reveal)
            lineHeight: 1.38
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }
    }
}
