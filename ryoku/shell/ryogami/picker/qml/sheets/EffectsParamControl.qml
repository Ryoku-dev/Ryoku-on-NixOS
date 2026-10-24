import QtQuick
import Ryoku.Ui.Singletons

// Rendered by the daemon's type: integer, number, dropdown or color.
Item {
    id: ctl

    property var param: ({})
    property var value: undefined
    property bool focused: false

    signal moved(var value)
    signal committed(var value)

    readonly property string _type: (ctl.param && ctl.param.type !== undefined)
        ? String(ctl.param.type)
        : (ctl.param && ctl.param.kind !== undefined) ? String(ctl.param.kind) : "number"
    readonly property bool _numeric: ctl._type === "integer" || ctl._type === "number"
    readonly property int _decimals: (ctl.param && ctl.param.decimals !== undefined)
        ? ctl.param.decimals : (ctl._type === "integer" ? 0 : 2)

    implicitWidth: 200 * Theme.scale
    implicitHeight: col.implicitHeight

    function _num(v, fb) { var n = Number(v); return isNaN(n) ? fb : n }
    function _fmt(v) {
        var n = ctl._num(v, 0)
        return ctl._decimals > 0 ? n.toFixed(ctl._decimals) : String(Math.round(n))
    }
    function _colour(v) {
        var s = (typeof v === "string") ? v.trim() : ""
        return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s) ? s : ""
    }

    Column {
        id: col
        width: ctl.width
        spacing: 8 * Theme.scale

        FolioRule { width: parent.width; alpha: 0.38 }

        Row {
            width: parent.width
            spacing: 8 * Theme.scale

            Text {
                width: parent.width - valueText.width - parent.spacing
                text: (ctl.param && ctl.param.label !== undefined ? ctl.param.label : "")
                font.family: Theme.sans
                font.weight: ctl.focused ? Font.DemiBold : Font.Medium
                font.pixelSize: Theme.fontBase
                color: ctl.focused ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.82)
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
            Text {
                id: valueText
                visible: ctl._numeric
                text: ctl._numeric ? ctl._fmt(slider.value) : ""
                font.family: Theme.display
                font.pixelSize: Theme.fontBody
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }
        }

        FolioSlider {
            id: slider
            visible: ctl._numeric
            width: parent.width
            focused: ctl.focused
            from: ctl._num(ctl.param ? ctl.param.min : 0, 0)
            to: ctl._num(ctl.param ? ctl.param.max : 1, 1)
            step: ctl._num(ctl.param ? ctl.param.step : 0, 0)
            Component.onCompleted: value = ctl._num(ctl.value, from)
            onMoved: (v) => ctl.moved(ctl._type === "integer" ? Math.round(v) : v)
            onReleased: (v) => ctl.committed(ctl._type === "integer" ? Math.round(v) : v)
        }

        Connections {
            target: ctl
            function onValueChanged() {
                if (ctl._numeric && !slider.dragging)
                    slider.value = ctl._num(ctl.value, slider.from)
            }
        }

        Text {
            visible: ctl._numeric
            width: parent.width
            text: ctl._fmt(ctl.param ? ctl.param.min : 0) + " - " + ctl._fmt(ctl.param ? ctl.param.max : 0)
            font.family: Theme.display
            font.pixelSize: Theme.fontTiny
            color: Theme.withAlpha(Theme.surfaceText, 0.38)
            renderType: Text.NativeRendering
        }

        ChoiceButtons {
            visible: ctl._type === "dropdown"
            width: parent.width
            value: ctl.value
            options: {
                var out = []
                var opts = (ctl.param && ctl.param.options) ? ctl.param.options : []
                for (var i = 0; i < opts.length; ++i) {
                    var o = opts[i]
                    var v = (o.mode !== undefined) ? o.mode : (o.value !== undefined ? o.value : o.label)
                    out.push({ value: v, label: (o.label !== undefined ? o.label : String(v)) })
                }
                return out
            }
            onSelected: (v) => ctl.committed(v)
        }

        Row {
            visible: ctl._type === "color"
            width: parent.width
            spacing: 7 * Theme.scale

            Rectangle {
                width: 38 * Theme.scale
                height: 31 * Theme.scale
                color: ctl._colour(field.text).length > 0 ? ctl._colour(field.text) : Theme.surfaceVariant
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.58)
            }
            TextField {
                id: field
                width: parent.width - 38 * Theme.scale - parent.spacing
                variant: "ghost"
                placeholder: "#rrggbb"
                Component.onCompleted: text = (ctl.value !== undefined) ? String(ctl.value) : ""
                onCommitted: (t) => ctl.committed(t)
            }
        }
    }
}
