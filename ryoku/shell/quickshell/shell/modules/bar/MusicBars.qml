pragma ComponentBehavior: Bound

import QtQuick
import shell.services

// A spectrum strip fed by the shared AudioBars cava feed. Two orientations, each
// spreading its bars evenly across the size the caller gives:
//   "vertical"   bars stand on the bottom and grow up, spread across `width`
//                (the card's wide sweep).
//   "horizontal" cava lines grow sideways from the centre, spread down `height`
//                (the vertical rail strip).
// Each bar averages the cava bands that fall in its slice, so a coarse strip
// reads the whole spectrum instead of sampling one spiky band. Bars are tinted
// on a low -> high ramp (the album-art accent in the card, the palette
// otherwise); loud tips lighten. The bars update only when the shared 30 fps
// feed publishes a frame and stop depending on its levels while silent.
Item {
    id: root

    property int bands: 24
    property bool running: true
    property real s: 1
    property string orient: "vertical"          // "vertical" | "horizontal"
    property color lowColor: Theme.primary
    property color highColor: Theme.tertiary

    readonly property bool horiz: root.orient === "horizontal"
    readonly property real sliver: Math.max(1.5, 2 * root.s)

    // sensible defaults; the caller sets the fill axis (width for a sweep,
    // height for a strip) and the bars spread to fit it.
    implicitWidth: root.horiz ? 24 * root.s : root.bands * 6 * root.s
    implicitHeight: root.horiz ? root.bands * 6 * root.s : 22 * root.s

    readonly property var shown: {
        if (!root.running || AudioBars.silent)
            return [];
        const out = [];
        for (let i = 0; i < root.bands; ++i)
            out.push(root.targetAt(i));
        return out;
    }

    function lerpColor(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1);
    }
    function bandColor(i, level) {
        var c = root.lerpColor(root.lowColor, root.highColor, root.bands > 1 ? i / (root.bands - 1) : 0.5);
        return Qt.lighter(c, 1 + 0.4 * level);
    }
    function levelAt(i) {
        var l = root.shown;
        return (l && i < l.length) ? l[i] : 0;
    }

    // average the cava bands that fall in this bar's slice, with a perceptual
    // boost so quiet bands still read.
    function targetAt(i) {
        if (!root.running)
            return 0;
        var src = AudioBars.levels;
        var n = AudioBars.bars;
        var lo = Math.floor(i / root.bands * n);
        var hi = Math.max(lo + 1, Math.floor((i + 1) / root.bands * n));
        var sum = 0, cnt = 0;
        for (var k = lo; k < hi && k < n; k++) {
            sum += (src && k < src.length) ? src[k] : 0;
            cnt++;
        }
        var v = cnt > 0 ? sum / cnt : 0;
        return Math.min(1, Math.pow(v, 0.7));
    }


    Repeater {
        model: root.bands
        Rectangle {
            required property int index
            readonly property real level: root.levelAt(index)
            // an even slice of the fill axis, the bar centred within it.
            readonly property real slot: (root.horiz ? root.height : root.width) / Math.max(1, root.bands)
            readonly property real thick: Math.max(2, Math.min(slot * 0.6, 7 * root.s))
            readonly property real grow: Math.max(root.sliver, (root.horiz ? root.width : root.height) * level)

            width: root.horiz ? grow : thick
            height: root.horiz ? thick : grow
            x: root.horiz ? (root.width - width) / 2 : (index * slot + (slot - thick) / 2)
            y: root.horiz ? (index * slot + (slot - thick) / 2) : (root.height - height)
            radius: Math.min(width, height) / 2
            antialiasing: true
            color: root.bandColor(index, level)

        }
    }
}
