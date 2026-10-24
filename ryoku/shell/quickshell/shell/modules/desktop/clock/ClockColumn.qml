pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk

/**
 * Column face: the hour stacked over the minute, both huge and tight, in Space
 * Grotesk. Made for depth -- the tall block sits to one side so the cut-out
 * subject rises beside it. The minute carries the accent so the two lines read
 * apart; ink is picked against the wallpaper beneath.
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
    readonly property real px: Math.round(150 * face.s)

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    Column {
        id: col
        spacing: Math.round(-0.2 * face.px)

        Text {
            text: face.t.hh
            color: face.ink
            font.family: Theme.font
            font.weight: Font.Bold
            font.pixelSize: face.px
            font.letterSpacing: Math.round(-2 * face.s)
        }
        Text {
            text: face.t.mm
            color: face.accent
            font.family: Theme.font
            font.weight: Font.Bold
            font.pixelSize: face.px
            font.letterSpacing: Math.round(-2 * face.s)
        }
        Row {
            spacing: Math.round(8 * face.s)
            topPadding: Math.round(0.1 * face.px)
            visible: Config.clockSeconds || !Config.clock24h
            Text {
                visible: Config.clockSeconds
                text: face.t.ss
                color: face.inkDim
                font.family: Theme.font
                font.weight: Font.DemiBold
                font.pixelSize: Math.round(face.px * 0.2)
            }
            Text {
                visible: !Config.clock24h
                text: face.t.ampm
                color: face.inkDim
                font.family: Theme.font
                font.weight: Font.DemiBold
                font.pixelSize: Math.round(face.px * 0.2)
                font.letterSpacing: 2
            }
        }
    }
}
