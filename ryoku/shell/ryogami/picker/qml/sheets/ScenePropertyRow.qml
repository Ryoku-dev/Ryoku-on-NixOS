import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    // { name, label, kind, value, default, overridden, min, max, step, options, condition, order }
    property var row: null
    // Below the threshold the label stacks above its control.
    property real available: 0

    signal committed(string name, var value)

    readonly property string _kind: root.row ? String(root.row.kind) : ""
    readonly property bool _isGroup: root._kind === "group"
    readonly property bool _isFlag: root._kind === "bool"
    readonly property bool _isRange: root._kind === "slider"
    readonly property bool _isCombo: root._kind === "combo"
    readonly property bool _isColour: root._kind === "color"
    readonly property bool stacked: root.available > 0 && root.available < 590 * Theme.scale
    // Wallpaper Engine names its stock colour property by an untranslated UI key.
    readonly property string _caption: !root.row ? ""
        : root.row.label === "ui_browse_properties_scheme_color" ? I18n.tr("Scheme colour")
        : String(root.row.label || root.row.name || "")

    property bool localBool: false
    property var localChoice: undefined
    property real rangeValue: 0
    property real colR: 1
    property real colG: 1
    property real colB: 1
    property string colorDraft: "1.000 1.000 1.000"

    implicitWidth: 200 * Theme.scale
    implicitHeight: layout.implicitHeight

    onRowChanged: root._seed()
    property int seedRevision: 0
    onSeedRevisionChanged: root._seed()
    Component.onCompleted: root._seed()

    function _seed() {
        if (!root.row)
            return
        root.localBool = !!root.row.value
        root.localChoice = root.row.value
        var n = Number(root.row.value)
        root.rangeValue = isFinite(n) ? n : 0
        var c = root._parseColour(root.row.value)
        root.colR = c.r; root.colG = c.g; root.colB = c.b
        root.colorDraft = root._encodeColour(c.r, c.g, c.b)
    }

    function _clamp01(x) { return Math.max(0, Math.min(1, x)) }
    function _parseColour(s) {
        var parts = String(s === undefined || s === null ? "" : s).trim().split(/\s+/)
        function f(x, d) { var n = parseFloat(x); return isFinite(n) ? root._clamp01(n) : d }
        return { r: f(parts[0], 1), g: f(parts[1], 1), b: f(parts[2], 1) }
    }
    function _encodeColour(r, g, b) {
        return r.toFixed(3) + " " + g.toFixed(3) + " " + b.toFixed(3)
    }
    function _formatNumber(v) {
        var x = Number(v)
        if (!isFinite(x))
            return String(v === undefined || v === null ? "" : v)
        return (Math.abs(x - Math.round(x)) < 1e-9) ? x.toFixed(0) : x.toFixed(3)
    }
    function _labelForValue(val) {
        var opts = (root.row && root.row.options) ? root.row.options : []
        for (var i = 0; i < opts.length; i++)
            if (opts[i].value === val)
                return opts[i].label !== undefined ? opts[i].label : root._formatNumber(val)
        return root._formatNumber(val)
    }
    function _defaultText() {
        if (!root.row)
            return ""
        switch (root._kind) {
        case "bool":  return root.row.default ? I18n.tr("On") : I18n.tr("Off")
        case "slider": return root._formatNumber(root.row.default)
        case "combo": return root._labelForValue(root.row.default)
        case "color": { var c = root._parseColour(root.row.default); return root._encodeColour(c.r, c.g, c.b) }
        }
        return root._formatNumber(root.row.default)
    }
    readonly property bool changed: {
        if (!root.row)
            return false
        switch (root._kind) {
        case "bool":  return root.localBool !== !!root.row.default
        case "slider": return Math.abs(root.rangeValue - Number(root.row.default)) > 1e-9
        case "combo": return root.localChoice !== root.row.default
        case "color": { var c = root._parseColour(root.row.default)
            return Math.abs(root.colR - c.r) > 1e-4 || Math.abs(root.colG - c.g) > 1e-4 || Math.abs(root.colB - c.b) > 1e-4 }
        }
        return false
    }

    function _commitColour() {
        var v = root._encodeColour(root.colR, root.colG, root.colB)
        root.colorDraft = v
        root.committed(root.row.name, v)
    }
    function _applyDraft() {
        var c = root._parseColour(root.colorDraft)
        root.colR = c.r; root.colG = c.g; root.colB = c.b
        root._commitColour()
    }
    function _setChannel(ch, v) {
        if (ch === "r") root.colR = v
        else if (ch === "g") root.colG = v
        else root.colB = v
        root.colorDraft = root._encodeColour(root.colR, root.colG, root.colB)
    }

    Column {
        id: layout
        width: root.width
        spacing: 6 * Theme.scale

        Text {
            visible: root._isGroup
            width: parent.width
            topPadding: 10 * Theme.scale
            bottomPadding: 10 * Theme.scale
            leftPadding: 8 * Theme.scale
            rightPadding: 8 * Theme.scale
            text: root._caption
            font.family: Theme.sans
            font.weight: Font.DemiBold
            font.pixelSize: Theme.fontBody
            color: Theme.withAlpha(Theme.surfaceText, 0.7)
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        FolioRule {
            visible: !root._isGroup
            width: parent.width
            alpha: 0.5
        }

        Item {
            id: body
            visible: !root._isGroup
            width: parent.width
            height: root.stacked
                ? (titleBlock.height + 6 * Theme.scale + controlHost.height)
                : Math.max(titleBlock.height, controlHost.height)

            Column {
                id: titleBlock
                anchors.top: parent.top
                anchors.left: parent.left
                width: root.stacked ? parent.width : 218 * Theme.scale
                spacing: 2 * Theme.scale

                Text {
                    width: parent.width
                    text: root._caption
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontLabel
                    color: Theme.surfaceText
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                }
                Text {
                    width: parent.width
                    visible: root.changed
                    text: I18n.tr("Author's default: %1").arg(root._defaultText())
                    font.family: Theme.sans
                    font.weight: Font.Normal
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.58)
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                }
            }

            Item {
                id: controlHost
                anchors.top: root.stacked ? titleBlock.bottom : parent.top
                anchors.topMargin: root.stacked ? 6 * Theme.scale : 0
                anchors.left: root.stacked ? parent.left : titleBlock.right
                anchors.leftMargin: root.stacked ? 0 : 20 * Theme.scale
                anchors.right: parent.right
                height: controlLoader.height

                Loader {
                    id: controlLoader
                    width: parent.width
                    height: implicitHeight
                    sourceComponent: root._isFlag ? flagControl
                        : root._isRange ? rangeControl
                        : root._isCombo ? comboControl
                        : root._isColour ? colourControl
                        : unsupportedControl
                }
            }
        }
    }

    Component {
        id: flagControl
        Item {
            width: parent ? parent.width : 0
            implicitHeight: flagBtn.implicitHeight
            FolioAction {
                id: flagBtn
                label: root.localBool ? I18n.tr("On") : I18n.tr("Off")
                active: root.localBool
                onTriggered: {
                    root.localBool = !root.localBool
                    root.committed(root.row.name, root.localBool)
                }
            }
        }
    }

    Component {
        id: rangeControl
        RowLayout {
            width: parent ? parent.width : 0
            spacing: 9 * Theme.scale
            FolioSlider {
                id: rangeSlider
                Layout.fillWidth: true
                from: root.row ? Number(root.row.min) : 0
                to: root.row ? Number(root.row.max) : 1
                step: root.row ? Number(root.row.step) : 0
                onMoved: (v) => root.rangeValue = v
                onReleased: (v) => { root.rangeValue = v; root.committed(root.row.name, v) }
                Component.onCompleted: value = root.rangeValue
                Connections {
                    target: root
                    function onRangeValueChanged() { if (!rangeSlider.dragging) rangeSlider.value = root.rangeValue }
                }
            }
            Text {
                Layout.preferredWidth: 56 * Theme.scale
                text: root._formatNumber(root.rangeValue)
                horizontalAlignment: Text.AlignRight
                font.family: Theme.display
                font.pixelSize: Theme.fontBase
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }
        }
    }

    Component {
        id: comboControl
        Item {
            width: parent ? parent.width : 0
            implicitHeight: chips.implicitHeight
            ChoiceButtons {
                id: chips
                width: parent.width
                value: root.localChoice
                options: (root.row && root.row.options) ? root.row.options : []
                onSelected: (v) => {
                    root.localChoice = v
                    root.committed(root.row.name, v)
                }
            }
        }
    }

    Component {
        id: colourControl
        Column {
            width: parent ? parent.width : 0
            spacing: 7 * Theme.scale

            RowLayout {
                width: parent.width
                height: implicitHeight
                spacing: 7 * Theme.scale
                Rectangle {
                    Layout.preferredWidth: 38 * Theme.scale
                    Layout.preferredHeight: 20 * Theme.scale
                    color: Qt.rgba(root.colR, root.colG, root.colB, 1)
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.38)
                }
                TextField {
                    id: draftField
                    Layout.fillWidth: true
                    variant: "ghost"
                    placeholder: "1.000 1.000 1.000"
                    text: root.colorDraft
                    onEdited: (t) => root.colorDraft = t
                    onCommitted: (t) => { root.colorDraft = t; root._applyDraft() }
                }
                FolioAction {
                    label: I18n.tr("Set colour")
                    onTriggered: root._applyDraft()
                }
            }

            RowLayout {
                width: parent.width
                height: implicitHeight
                spacing: 7 * Theme.scale
                Text {
                    Layout.preferredWidth: 58 * Theme.scale
                    text: I18n.tr("Red")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                }
                FolioSlider {
                    id: rSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    step: 0.001
                    onMoved: (v) => root._setChannel("r", v)
                    onReleased: (v) => { root._setChannel("r", v); root._commitColour() }
                    Component.onCompleted: value = root.colR
                    Connections {
                        target: root
                        function onColRChanged() { if (!rSlider.dragging) rSlider.value = root.colR }
                    }
                }
                Text {
                    Layout.preferredWidth: 48 * Theme.scale
                    text: root.colR.toFixed(3)
                    horizontalAlignment: Text.AlignRight
                    font.family: Theme.display
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                }
            }
            RowLayout {
                width: parent.width
                height: implicitHeight
                spacing: 7 * Theme.scale
                Text {
                    Layout.preferredWidth: 58 * Theme.scale
                    text: I18n.tr("Green")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                }
                FolioSlider {
                    id: gSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    step: 0.001
                    onMoved: (v) => root._setChannel("g", v)
                    onReleased: (v) => { root._setChannel("g", v); root._commitColour() }
                    Component.onCompleted: value = root.colG
                    Connections {
                        target: root
                        function onColGChanged() { if (!gSlider.dragging) gSlider.value = root.colG }
                    }
                }
                Text {
                    Layout.preferredWidth: 48 * Theme.scale
                    text: root.colG.toFixed(3)
                    horizontalAlignment: Text.AlignRight
                    font.family: Theme.display
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                }
            }
            RowLayout {
                width: parent.width
                height: implicitHeight
                spacing: 7 * Theme.scale
                Text {
                    Layout.preferredWidth: 58 * Theme.scale
                    text: I18n.tr("Blue")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                }
                FolioSlider {
                    id: bSlider
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    step: 0.001
                    onMoved: (v) => root._setChannel("b", v)
                    onReleased: (v) => { root._setChannel("b", v); root._commitColour() }
                    Component.onCompleted: value = root.colB
                    Connections {
                        target: root
                        function onColBChanged() { if (!bSlider.dragging) bSlider.value = root.colB }
                    }
                }
                Text {
                    Layout.preferredWidth: 48 * Theme.scale
                    text: root.colB.toFixed(3)
                    horizontalAlignment: Text.AlignRight
                    font.family: Theme.display
                    font.pixelSize: Theme.fontBase
                    color: Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                }
            }
        }
    }

    Component {
        id: unsupportedControl
        Item {
            width: parent ? parent.width : 0
            implicitHeight: note.implicitHeight
            Text {
                id: note
                width: parent.width
                text: I18n.tr("Not adjustable here")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBase
                color: Theme.withAlpha(Theme.surfaceText, 0.48)
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
        }
    }
}
