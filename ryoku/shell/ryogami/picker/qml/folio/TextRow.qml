import QtQuick
import Ryoku.Ui.Singletons

// variant: "" or "text" plain, "path" with a folder glyph, "secret" masked with a reveal toggle.
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
    readonly property string variant: row.control.variant ? row.control.variant : "text"
    readonly property var _val: row.bound ? sv.value : row.boundValue
    readonly property bool atDefault: row.bound ? sv.isDefault : true
    readonly property bool _secret: row.variant === "secret"
    readonly property bool _path: row.variant === "path"

    property bool _reveal: false

    implicitHeight: col.implicitHeight
    function resetValue() { if (row.bound) sv.reset() }
    function _apply(v) { if (row.bound) sv.set(v); else row.edited(v) }

    SettingValue { id: sv; key: row.bound ? row.rk : "" }

    // Reflect an external change into the field unless the user is typing.
    onRkChanged: input.text = row._valStr()
    Connections {
        target: sv
        enabled: row.bound
        function onValueChanged() { if (!input.activeFocus) input.text = row._valStr() }
    }
    function _valStr() { return (row._val === undefined || row._val === null) ? "" : String(row._val) }
    Component.onCompleted: input.text = row._valStr()

    Column {
        id: col
        width: row.width
        spacing: 4 * Theme.scale

        Item {
            width: parent.width
            height: title.implicitHeight

            Text {
                id: title
                anchors.left: parent.left
                anchors.right: reset.left
                anchors.rightMargin: 10 * Theme.scale
                anchors.verticalCenter: parent.verticalCenter
                text: row.control.label ? row.control.label : ""
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontField
                color: Theme.withAlpha(Theme.surfaceText, row.enabled ? row.reveal : 0.4 * row.reveal)
                elide: Text.ElideRight
            }
            ResetChip {
                id: reset
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: row.bound && !row.atDefault && row.enabled
                onTriggered: row.resetValue()
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

        Rectangle {
            id: box
            width: Math.min(parent.width, 420 * Theme.scale)
            height: input.implicitHeight + 12 * Theme.scale
            radius: Theme.radius
            color: Theme.withAlpha(Theme.surfaceText, 0.05)
            border.width: input.activeFocus ? 2 : 1
            border.color: input.activeFocus ? Theme.withAlpha(Theme.surfaceText, 0.7)
                        : row.enabled ? Theme.withAlpha(Theme.outline, 0.4)
                        : Theme.withAlpha(Theme.outline, 0.18)
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }

            Text {
                id: lead
                visible: row._path
                anchors.left: parent.left
                anchors.leftMargin: 7 * Theme.scale
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf07b"
                font.family: Theme.icon
                font.pixelSize: Theme.fontLabel
                color: Theme.withAlpha(Theme.surfaceText, input.activeFocus ? 0.9 : 0.5)
                renderType: Text.NativeRendering
            }

            TextInput {
                id: input
                anchors.left: parent.left
                anchors.leftMargin: (row._path ? 26 : 7) * Theme.scale
                anchors.right: eye.visible ? eye.left : parent.right
                anchors.rightMargin: 7 * Theme.scale
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                enabled: row.enabled
                echoMode: (row._secret && !row._reveal) ? TextInput.Password : TextInput.Normal
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontLabel
                color: row.enabled ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.4)
                selectionColor: Theme.withAlpha(Theme.surfaceText, 0.24)
                selectedTextColor: Theme.surfaceText
                selectByMouse: true
                renderType: Text.NativeRendering
                onEditingFinished: row._apply(text)
                Keys.onReturnPressed: row._apply(text)
                Keys.onEnterPressed: row._apply(text)

                Text {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    verticalAlignment: Text.AlignVCenter
                    text: row.control.placeholder ? row.control.placeholder : ""
                    font: input.font
                    color: Theme.withAlpha(Theme.surfaceText, 0.48)
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
            }

            Text {
                id: eye
                visible: row._secret
                anchors.right: parent.right
                anchors.rightMargin: 7 * Theme.scale
                anchors.verticalCenter: parent.verticalCenter
                text: row._reveal ? "\uf070" : "\uf06e"
                font.family: Theme.icon
                font.pixelSize: Theme.fontLabel
                color: Theme.withAlpha(Theme.surfaceText, eyeArea.containsMouse ? 0.9 : 0.55)
                renderType: Text.NativeRendering
                MouseArea {
                    id: eyeArea
                    anchors.fill: parent
                    anchors.margins: -4 * Theme.scale
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row._reveal = !row._reveal
                }
            }
        }
    }
}
