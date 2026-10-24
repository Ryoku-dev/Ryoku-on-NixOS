pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk

/**
 * Outline face: the time as giant hollow-stroked numerals, so the cut-out subject
 * reads through and around the digits -- the most depth-native face. A filled
 * accent colon anchors it. Ink is picked against the wallpaper beneath.
 */
Item {
    id: face

    property real underL: Scheme.wallLstar
    // a pinned colour ("" = follow wallpaper) paints this face's own ink.
    property string inkColorA: ""
    property real s: 1
    readonly property color ink: Theme.inkOn2(face.underL, face.inkColorA)
    readonly property color accent: Clk.pickAccent(Config.clockAccent, Theme.accentOn2(face.underL, face.inkColorA), Theme.brand, face.ink)
    readonly property var t: Clk.parts(Now.date, Config.clock24h)
    readonly property real px: Math.round(190 * face.s)

    // hollow outlined text: a hidden Text measures the run, a Canvas strokes it.
    component Hollow: Item {
        property string txt: ""
        property color col: "#ffffff"
        property real ps: 90
        property real lw: 3
        readonly property string fam: Theme.font
        implicitWidth: meas.implicitWidth + lw * 2
        implicitHeight: ps * 1.02
        Text {
            id: meas
            visible: false
            text: parent.txt
            font.family: parent.fam
            font.weight: Font.Bold
            font.pixelSize: parent.ps
        }
        Canvas {
            anchors.fill: parent
            readonly property var key: [parent.txt, parent.ps, parent.lw, parent.col]
            onKeyChanged: requestPaint()
            onPaint: {
                var c = getContext("2d");
                c.reset();
                c.clearRect(0, 0, width, height);
                c.font = "700 " + parent.ps + "px '" + parent.fam + "'";
                c.textBaseline = "alphabetic";
                c.lineWidth = parent.lw;
                c.strokeStyle = parent.col;
                c.lineJoin = "round";
                var x = parent.lw;
                var y = parent.ps * 0.82;
                for (var i = 0; i < parent.txt.length; i++) {
                    c.strokeText(parent.txt[i], x, y);
                    x += c.measureText(parent.txt[i]).width;
                }
            }
            Component.onCompleted: requestPaint()
        }
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: Math.round(6 * face.s)
        Hollow {
            anchors.verticalCenter: parent.verticalCenter
            txt: face.t.hh
            col: face.ink
            ps: face.px
            lw: Math.max(2, 3 * face.s)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ":"
            color: face.accent
            font.family: Theme.font
            font.weight: Font.Bold
            font.pixelSize: face.px
        }
        Hollow {
            anchors.verticalCenter: parent.verticalCenter
            txt: face.t.mm
            col: face.ink
            ps: face.px
            lw: Math.max(2, 3 * face.s)
        }
    }
}
