pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "../Singletons"
import "lib/clock.js" as Clk

/**
 * Banner face: NibrasShell's wide clock, ported directly -- one line reading
 * "hh:mm AP - MM/DD", big and calm, made to pair with depth. A soft adaptive
 * halo (dark behind light ink, light behind dark) keeps the time legible on any
 * wallpaper, even in the moment a new one is still being recoloured.
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

    readonly property var t: Clk.parts(Now.date, Config.clock24h)
    readonly property var dt: Clk.dateParts(Now.date)
    readonly property real px: Math.round(150 * face.s)
    readonly property real track: Math.round(face.px * -0.01)

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    width: implicitWidth
    height: implicitHeight

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: face.underL < 50 ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.6)
        shadowBlur: 0.7
        shadowVerticalOffset: 0
        shadowHorizontalOffset: 0
    }

    Row {
        id: row
        spacing: Math.round(face.px * 0.16)

        // hh:mm, tight
        Row {
            id: hm
            spacing: 0
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: face.t.hh
                color: face.ink
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: face.px
                font.letterSpacing: face.track
            }
            Text {
                text: ":"
                color: face.accent
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: face.px
                font.letterSpacing: face.track
            }
            Text {
                text: face.t.mm
                color: face.ink
                font.family: Theme.font
                font.weight: Font.Bold
                font.pixelSize: face.px
                font.letterSpacing: face.track
            }
        }

        // AM/PM, small, on the time's baseline (12h only)
        Text {
            visible: !Config.clock24h
            anchors.bottom: hm.bottom
            anchors.bottomMargin: Math.round(face.px * 0.14)
            text: face.t.ampm
            color: face.inkDim
            font.family: Theme.font
            font.weight: Font.DemiBold
            font.pixelSize: Math.round(face.px * 0.24)
            font.letterSpacing: 2
        }

        // separator
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u2013"
            color: face.inkDim
            font.family: Theme.font
            font.weight: Font.Bold
            font.pixelSize: face.px
        }

        // MM/DD
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Clk.pad2(face.dt.mon + 1) + "/" + Clk.pad2(face.dt.dom)
            color: face.ink
            font.family: Theme.font
            font.weight: Font.Bold
            font.pixelSize: face.px
            font.letterSpacing: face.track
        }
    }
}
