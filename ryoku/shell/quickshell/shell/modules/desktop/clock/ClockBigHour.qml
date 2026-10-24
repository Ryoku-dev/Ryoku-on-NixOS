pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk
import shell.services as Svc

/**
 * Big-hour face: a giant hour with the minute (solid) stacked over the second
 * (hollow outline) at its right, and the weekday/day plus the month (hollow
 * outline) down its left. Deliberately its own visual language -- bright ink,
 * heavy Inter Display, a hollow-stroked month -- rather than the wallpaper
 * palette, so it reads as the reference design on any backdrop.
 */
Item {
    id: face

    property real underL: Scheme.wallLstar
    // a pinned colour ("" = the reference bright ink) paints this face's ink.
    property string inkColorA: ""
    property real s: 1
    readonly property color ink: face.inkColorA !== "" ? face.inkColorA : "#f6f7fa"

    readonly property var t: Clk.parts(Now.secondDate, Config.clock24h)
    readonly property var dp: Clk.dateParts(Now.date, Svc.Config.formatLoc)
    readonly property bool showSecs: Config.clockSeconds

    // hollow outlined text: a hidden Text measures the run, a Canvas strokes it.
    component Hollow: Item {
        property string txt: ""
        property real ps: 90
        property real weight: Font.Black
        property real lw: 2.2
        property real track: 0
        readonly property string fam: "Inter Display"
        implicitWidth: meas.implicitWidth + lw * 2
        implicitHeight: ps * 1.0
        Text {
            id: meas; visible: false; text: parent.txt
            font.family: parent.fam; font.weight: parent.weight
            font.pixelSize: parent.ps; font.letterSpacing: parent.track
        }
        Canvas {
            anchors.fill: parent
            readonly property var key: [parent.txt, parent.ps, parent.lw]
            onKeyChanged: requestPaint()
            onPaint: {
                var c = getContext("2d"); c.reset(); c.clearRect(0, 0, width, height);
                var wt = parent.weight >= Font.Black ? 900 : (parent.weight >= Font.Bold ? 700 : 400);
                c.font = wt + " " + parent.ps + "px '" + parent.fam + "'";
                c.textBaseline = "alphabetic"; c.lineWidth = parent.lw;
                c.strokeStyle = face.ink; c.lineJoin = "round";
                var x = parent.lw, y = parent.ps * 0.80;
                for (var i = 0; i < parent.txt.length; i++) {
                    c.strokeText(parent.txt[i], x, y);
                    x += c.measureText(parent.txt[i]).width + parent.track;
                }
            }
            Component.onCompleted: requestPaint()
        }
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: Math.round(22 * face.s)

        Column {
            anchors.bottom: parent.bottom
            spacing: Math.round(2 * face.s)
            Text {
                text: (face.dp.weekdayShort + ", " + Clk.pad2(face.dp.dom)).toUpperCase()
                color: face.ink
                font.family: "Inter Display"; font.weight: Font.Bold
                font.pixelSize: Math.round(33 * face.s); font.letterSpacing: 2
            }
            Hollow {
                txt: face.dp.month.toUpperCase(); ps: Math.round(74 * face.s)
                lw: Math.max(1.4, 2.0 * face.s); track: 1
            }
            Item { width: 1; height: Math.round(30 * face.s) }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: face.t.hh; color: face.ink
            font.family: "Inter Display"; font.weight: Font.Black
            font.pixelSize: Math.round(300 * face.s); font.letterSpacing: Math.round(-8 * face.s)
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: face.t.mm; color: face.ink
                font.family: "Inter Display"; font.weight: Font.Black
                font.pixelSize: Math.round(116 * face.s); font.letterSpacing: Math.round(-4 * face.s)
            }
            Hollow {
                visible: face.showSecs
                txt: face.t.ss; ps: Math.round(116 * face.s)
                lw: Math.max(1.8, 2.6 * face.s)
            }
        }
    }
}
