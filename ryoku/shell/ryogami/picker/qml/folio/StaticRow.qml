import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var control: ({})
    property var state
    property real reveal: 1
    property var values: ({})
    property string valueText: ""

    readonly property bool _fixedKey: typeof row.control.id === "string" && row.control.id.indexOf("keybinds.fixed") === 0
    readonly property bool _conflict: typeof row.control.id === "string" && row.control.id.indexOf("keybinds.conflict") === 0

    implicitHeight: col.implicitHeight

    function _fill(str) {
        if (!str)
            return "";
        var args = row.control.args ? row.control.args : [];
        return String(str).replace(/%(\d)/g, function (m, d) {
            var name = args[Number(d) - 1];
            var v = name !== undefined ? row.values[name] : undefined;
            return (v === undefined || v === null) ? "\u2014" : String(v);
        });
    }

    Column {
        id: col
        width: row.width
        spacing: 5 * Theme.scale

        Row {
            width: parent.width
            visible: row._fixedKey
            spacing: 10 * Theme.scale

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: keyText.implicitWidth + 18 * Theme.scale
                height: keyText.implicitHeight + 10 * Theme.scale
                color: Theme.withAlpha(Theme.surfaceContainer, 0.9)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.4)
                Text {
                    id: keyText
                    anchors.centerIn: parent
                    text: row.control.label ? row.control.label : ""
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontLabel
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - keyText.width - 40 * Theme.scale
                text: row.control.help ? row.control.help : ""
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBase
                color: Theme.withAlpha(Theme.surfaceText, 0.68 * row.reveal)
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
        }

        Text {
            width: parent.width
            visible: !row._fixedKey && row.control.label && row.control.label.length > 0
            text: row._fill(row.control.label)
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontField
            color: Theme.withAlpha(row._conflict ? Theme.tertiary : Theme.surfaceText, row.reveal)
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        Rectangle {
            width: parent.width
            visible: !row._fixedKey && valueLabel.text.length > 0
            height: valueLabel.implicitHeight + 14 * Theme.scale
            color: Theme.withAlpha(Theme.surfaceContainer, 0.55)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.32)

            Text {
                id: valueLabel
                anchors.fill: parent
                anchors.leftMargin: 10 * Theme.scale
                anchors.rightMargin: 10 * Theme.scale
                verticalAlignment: Text.AlignVCenter
                text: row.valueText.length > 0 ? row.valueText : row._fill(row.control.help)
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBody
                color: Theme.withAlpha(Theme.surfaceText, 0.7 * row.reveal)
                lineHeight: 1.35
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
        }
    }
}
