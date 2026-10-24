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
    readonly property bool atDefault: row.bound ? sv.isDefault : true
    readonly property bool _palette: row.control.dynamic === "themes" || row.control.dynamic === "recolourThemes"

    // Depends on the provider revision so live entries refresh the buttons in place.
    readonly property var _opts: (row.options && row.options.revision >= 0)
        ? row.options.optionsFor(row.control)
        : (row.control.options ? row.control.options : [])

    implicitHeight: col.implicitHeight
    function resetValue() { if (row.bound) sv.reset() }
    function _apply(v) { if (row.bound) sv.set(v); else row.edited(v) }

    SettingValue { id: sv; key: row.bound ? row.rk : "" }

    Column {
        id: col
        width: row.width
        spacing: 6 * Theme.scale

        Item {
            width: parent.width
            height: title.implicitHeight
            visible: title.text.length > 0

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

        ChoiceButtons {
            width: parent.width
            enabled: row.enabled
            mode: row.control.kind === "dropdown" ? "dropdown" : "chips"
            showStrip: row._palette
            options: row._opts
            value: row._val
            onSelected: (v) => row._apply(v)
        }
    }
}
