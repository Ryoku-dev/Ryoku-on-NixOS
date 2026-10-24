import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: swatches

    property string source: ""
    property real available: 420

    signal picked(string newSource)

    implicitHeight: 21 * Theme.scale
    implicitWidth: swatches.available * Theme.scale

    readonly property real _avail: swatches.width > 0 ? swatches.width : swatches.available * Theme.scale
    readonly property var _active: swatches._parse(swatches.source)

    readonly property var _names: ({
        red: 0, orange: 1, yellow: 2, lime: 3, chartreuse: 3, green: 4, spring: 5,
        cyan: 6, teal: 6, azure: 7, blue: 8, violet: 9, purple: 9, magenta: 10,
        pink: 11, rose: 11, gray: 99, grey: 99
    })

    function _bucketOf(token) {
        if (/^\d+$/.test(token)) {
            var n = parseInt(token)
            return (n === 99 || (n >= 0 && n <= 11)) ? n : -1
        }
        return swatches._names[token] !== undefined ? swatches._names[token] : -1
    }

    function _parse(src) {
        var toks = String(src || "").split(/\s+/)
        for (var i = 0; i < toks.length; ++i) {
            var low = toks[i].toLowerCase()
            if (low.indexOf("color:") === 0 || low.indexOf("colour:") === 0) {
                var value = toks[i].substring(toks[i].indexOf(":") + 1)
                var parts = value.split(",")
                var out = []
                for (var j = 0; j < parts.length; ++j) {
                    var b = swatches._bucketOf(parts[j].trim().toLowerCase())
                    if (b >= 0 && out.indexOf(b) < 0)
                        out.push(b)
                }
                return out
            }
        }
        return []
    }

    function _toggle(bucket) {
        var cur = swatches._parse(swatches.source).slice()
        var at = cur.indexOf(bucket)
        if (at >= 0)
            cur.splice(at, 1)
        else
            cur.push(bucket)
        cur.sort(function(a, b) { return a - b })

        var toks = String(swatches.source || "").split(/\s+/).filter(function(t) {
            var low = t.toLowerCase()
            return t.length > 0 && low.indexOf("color:") !== 0 && low.indexOf("colour:") !== 0
        })
        if (cur.length > 0)
            toks.push("color:" + cur.join(","))
        swatches.picked(toks.join(" "))
    }

    function _swatchColor(bucket, active) {
        if (bucket === 99)
            return Qt.hsla(0, 0, active ? 0.68 : 0.46, 1)
        return Qt.hsla((bucket * 30) / 360, active ? 0.78 : 0.52, active ? 0.58 : 0.44, 1)
    }

    Row {
        spacing: 3 * Theme.scale

        Repeater {
            model: 13

            delegate: Rectangle {
                required property int index
                readonly property int bucket: index < 12 ? index : 99
                readonly property bool active: swatches._active.indexOf(bucket) >= 0

                width: Math.max(17 * Theme.scale,
                    Math.min(38 * Theme.scale, (swatches._avail - 3 * Theme.scale * 12) / 13))
                height: 21 * Theme.scale
                color: swatches._swatchColor(bucket, active)
                border.width: 1
                border.color: active ? Theme.withAlpha(Theme.surfaceText, 0.9)
                                     : Theme.withAlpha(Theme.outline, 0.42)

                opacity: hoverArea.containsMouse ? 0.85 : 1

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: swatches._toggle(parent.bucket)
                }
            }
        }
    }
}
