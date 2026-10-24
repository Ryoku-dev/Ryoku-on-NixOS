pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk

// minimal face. thin airy Inter time, wide tracking, a short accent rule
// below it. earns its place through type + spacing, no ornament. seconds /
// AM-PM (when on) sit as a quiet caption.
Item {
    id: face

    // the widget floats on the wallpaper, so its ink is picked against the patch
    // of picture under it. WidgetSlot measures it and pushes it in.
    property real underL: Scheme.wallLstar
    // a pinned colour ("" = follow wallpaper) paints this face's own ink.
    property string inkColorA: ""
    property real s: 1
    readonly property color ink:     Theme.inkOn2(face.underL, face.inkColorA)
    readonly property color inkDim:  Theme.inkDimOn2(face.underL, face.inkColorA)
    readonly property color inkSoft: Theme.inkSoftOn2(face.underL, face.inkColorA)

    readonly property var t: Clk.parts(Now.secondDate, Config.clock24h)
    readonly property color accent: Clk.pickAccent(Config.clockAccent, Theme.accentOn2(face.underL, face.inkColorA), Theme.brand, face.ink)
    readonly property real px: Math.round(82 * face.s)
    readonly property string caption: (Config.clockSeconds ? face.t.ss : "")
        + (Config.clockSeconds && !Config.clock24h ? "  " : "")
        + (!Config.clock24h ? face.t.ampm.toLowerCase() : "")

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    Column {
        id: col
        spacing: Math.round(10 * face.s)

        Text {
            id: time
            text: face.t.hh + ":" + face.t.mm
            color: face.ink
            font.family: Theme.font
            font.pixelSize: face.px
            font.weight: Font.Light
            font.letterSpacing: Math.round(2 * face.s)
        }

        Rectangle {
            width: Math.round(time.implicitWidth * 0.34)
            height: Math.max(2, Math.round(3 * face.s))
            radius: height / 2
            color: face.accent
        }

        Text {
            visible: face.caption.length > 0
            text: face.caption
            color: face.inkDim
            font.family: Theme.font
            font.pixelSize: Math.round(face.px * 0.22)
            font.weight: Font.Medium
            font.letterSpacing: Math.round(3 * face.s)
        }
    }
}
