import QtQuick
import Ryoku.Ui.Singletons

// Value is {w, h}, 0 meaning unbounded; unbound, the caller supplies boundValue and receives edited().
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

    readonly property var _pair: {
        var v = row._val;
        if (v && typeof v === "object")
            return { w: Number(v.w !== undefined ? v.w : v.width) || 0, h: Number(v.h !== undefined ? v.h : v.height) || 0 };
        return { w: 0, h: 0 };
    }

    implicitHeight: col.implicitHeight
    function resetValue() { if (row.bound) sv.reset() }
    function _apply(w, h) {
        var out = { w: w || 0, h: h || 0 };
        if (row.bound) sv.set(out); else row.edited(out);
    }

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

        Row {
            spacing: 8 * Theme.scale

            NumberField {
                id: wField
                anchors.verticalCenter: parent.verticalCenter
                enabled: row.enabled
                unit: I18n.tr("w")
                placeholder: I18n.tr("Any")
                value: row._pair.w > 0 ? row._pair.w : null
                onCommitted: (v) => row._apply(v === null ? 0 : v, row._pair.h)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u00d7"
                font.family: Theme.display
                font.pixelSize: Theme.fontHead
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                renderType: Text.NativeRendering
            }
            NumberField {
                id: hField
                anchors.verticalCenter: parent.verticalCenter
                enabled: row.enabled
                unit: I18n.tr("h")
                placeholder: I18n.tr("Any")
                value: row._pair.h > 0 ? row._pair.h : null
                onCommitted: (v) => row._apply(row._pair.w, v === null ? 0 : v)
            }
        }
    }
}
