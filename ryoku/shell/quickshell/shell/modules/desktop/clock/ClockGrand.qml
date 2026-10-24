pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk

/**
 * Grand face: one giant time in the display serif (Fraunces), set editorial and
 * quiet. Made for depth -- a large, calm serif the cut-out subject can drift
 * across like a magazine cover. The colon carries the accent; ink is picked
 * against the wallpaper beneath it, so it reads on any backdrop.
 */
Item {
    id: face

    property real underL: Scheme.wallLstar
    // a pinned colour ("" = follow wallpaper) paints this face's own ink.
    property string inkColorA: ""
    property real s: 1
    readonly property color ink: Theme.inkOn2(face.underL, face.inkColorA)
    readonly property color inkDim: Theme.inkDimOn2(face.underL, face.inkColorA)
    readonly property color accent: Clk.pickAccent(Config.clockAccent, Theme.accentOn2(face.underL, face.inkColorA), Theme.brand, face.ink)

    readonly property var t: Clk.parts(Now.secondDate, Config.clock24h)
    readonly property real px: Math.round(168 * face.s)
    readonly property bool side: Config.clockSeconds || !Config.clock24h

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: face.side ? Math.round(18 * face.s) : 0

        Row {
            id: hm
            spacing: 0
            Text {
                text: face.t.hh
                color: face.ink
                font.family: Theme.display
                font.weight: Font.Medium
                font.pixelSize: face.px
            }
            Text {
                text: ":"
                color: face.accent
                font.family: Theme.display
                font.weight: Font.Medium
                font.pixelSize: face.px
            }
            Text {
                text: face.t.mm
                color: face.ink
                font.family: Theme.display
                font.weight: Font.Medium
                font.pixelSize: face.px
            }
        }

        Item {
            height: hm.height
            width: Math.max(secs.implicitWidth, ampm.implicitWidth)
            visible: face.side
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(6 * face.s)
                Text {
                    id: secs
                    visible: Config.clockSeconds
                    text: face.t.ss
                    color: face.accent
                    font.family: Theme.display
                    font.pixelSize: Math.round(face.px * 0.26)
                    font.weight: Font.Medium
                }
                Text {
                    id: ampm
                    visible: !Config.clock24h
                    text: face.t.ampm
                    color: face.inkDim
                    font.family: Theme.font
                    font.pixelSize: Math.round(face.px * 0.15)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 3
                }
            }
        }
    }
}
