pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"
import "lib/clock.js" as Clk
import shell.services as Svc

/**
 * Metal face: a heavy condensed time over a single meta line
 * "PM | Weekday | Condition, Temp". Bright ink, Inter Display Black, so it
 * reads as the reference design rather than the wallpaper palette. The weather
 * clause hides itself when the daemon has no reading yet.
 */
Item {
    id: face

    property real underL: Scheme.wallLstar
    // a pinned colour ("" = the reference bright ink) paints this face's ink.
    property string inkColorA: ""
    property real s: 1
    readonly property color ink: face.inkColorA !== "" ? face.inkColorA : "#f4f6f8"

    readonly property var t: Clk.parts(Now.date, Config.clock24h)
    readonly property var dp: Clk.dateParts(Now.date, Svc.Config.formatLoc)

    readonly property string wx: Svc.Weather.available
        ? (Svc.Weather.condition + " , " + Svc.Weather.tempNow + "\u00b0" + (Svc.Weather.temp.slice(-1)))
        : ""
    readonly property string meta: (Config.clock24h ? "" : (face.t.ampm + "  |  "))
        + face.dp.weekday
        + (face.wx.length > 0 ? ("  |  " + face.wx) : "")

    implicitWidth: col.implicitWidth
    implicitHeight: col.implicitHeight

    Column {
        id: col
        spacing: Math.round(12 * face.s)
        Text {
            text: face.t.hh + ":" + face.t.mm
            color: face.ink
            font.family: "Inter Display"; font.weight: Font.Black
            font.pixelSize: Math.round(132 * face.s); font.letterSpacing: Math.round(-2 * face.s)
        }
        Text {
            text: face.meta
            color: face.ink
            font.family: "Inter Display"; font.weight: Font.Bold
            font.pixelSize: Math.round(25 * face.s); font.letterSpacing: 0.5
        }
    }
}
