import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: picker

    property string value: "#ffffff"
    property string label: ""
    property bool expanded: false
    signal chosen(string value)

    property var draftHsv: ({ h: 0, s: 0, v: 1 })
    property string draftHex: picker.normalized(picker.value)

    implicitHeight: col.implicitHeight

    onValueChanged: {
        if (!picker.expanded) {
            picker.draftHex = picker.normalized(picker.value)
            picker.draftHsv = picker.toHsv(picker.draftHex)
        }
    }

    Component.onCompleted: picker.draftHsv = picker.toHsv(picker.draftHex)

    function normalized(text) {
        var s = String(text || "").trim()
        if (s.charAt(0) !== "#")
            s = "#" + s
        return /^#[0-9a-fA-F]{6}$/.test(s) ? s.toUpperCase() : "#FFFFFF"
    }

    function toHsv(hex) {
        var c = Qt.color(picker.normalized(hex))
        var r = c.r, g = c.g, b = c.b
        var max = Math.max(r, g, b), min = Math.min(r, g, b)
        var d = max - min, h = 0
        if (d > 0) {
            if (max === r)
                h = 60 * (((g - b) / d) % 6)
            else if (max === g)
                h = 60 * (((b - r) / d) + 2)
            else
                h = 60 * (((r - g) / d) + 4)
        }
        if (h < 0)
            h += 360
        return { h: h, s: max === 0 ? 0 : d / max, v: max }
    }

    function toHex(hsv) {
        var c = Qt.hsva((Number(hsv.h) || 0) / 360,
                        Math.max(0, Math.min(1, Number(hsv.s) || 0)),
                        Math.max(0, Math.min(1, Number(hsv.v) || 0)), 1)
        function part(v) {
            var s = Math.round(v * 255).toString(16).toUpperCase()
            return s.length < 2 ? "0" + s : s
        }
        return "#" + part(c.r) + part(c.g) + part(c.b)
    }

    function updateDraft(next) {
        picker.draftHsv = next
        picker.draftHex = picker.toHex(next)
    }

    function commit(text) {
        var s = String(text || "").trim()
        if (!/^#?[0-9a-fA-F]{6}$/.test(s))
            return
        picker.draftHex = picker.normalized(s)
        picker.draftHsv = picker.toHsv(picker.draftHex)
        picker.chosen(picker.draftHex)
    }

    Column {
        id: col
        width: picker.width
        spacing: 8 * Theme.scale

        Row {
            width: parent.width
            spacing: 8 * Theme.scale

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 28 * Theme.scale
                height: 28 * Theme.scale
                radius: Theme.radius
                color: picker.draftHex
                border.width: 1
                border.color: Theme.withAlpha(Theme.outline, 0.6)
                Behavior on color { ColorAnimation { duration: Theme.fast } }
            }

            TextField {
                id: hexField
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(150 * Theme.scale, Math.max(92 * Theme.scale,
                    parent.width - colourButton.width - 44 * Theme.scale))
                variant: "field"
                text: picker.draftHex
                placeholder: I18n.tr("#RRGGBB")
                onCommitted: (text) => picker.commit(text)
            }

            FolioAction {
                id: colourButton
                anchors.verticalCenter: parent.verticalCenter
                label: picker.expanded ? I18n.tr("Done") : (picker.label.length > 0 ? picker.label : I18n.tr("Choose"))
                onTriggered: {
                    picker.expanded = !picker.expanded
                    if (picker.expanded)
                        picker.draftHsv = picker.toHsv(picker.draftHex)
                }
            }
        }

        Item {
            width: parent.width
            height: picker.expanded ? wheelCol.implicitHeight : 0
            opacity: picker.expanded ? 1 : 0
            clip: true
            Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Theme.revealEasing } }
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }

            Column {
                id: wheelCol
                width: parent.width
                spacing: 7 * Theme.scale

                ColorWheel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(184 * Theme.scale, wheelCol.width)
                    height: width
                    hsv: picker.draftHsv
                    onHue: (degrees) => picker.updateDraft({ h: degrees, s: picker.draftHsv.s, v: picker.draftHsv.v })
                    onSv: (saturation, value) => picker.updateDraft({ h: picker.draftHsv.h, s: saturation, v: value })
                    onDragEnd: picker.commit(picker.draftHex)
                }

                Text {
                    width: parent.width
                    text: I18n.tr("Drag the ring for hue and the square for saturation and brightness.")
                    font.family: Theme.sans
                    font.weight: Font.Normal
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
