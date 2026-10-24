pragma ComponentBehavior: Bound
import QtQuick
import "../Singletons"

// Shape: a single decorative mark on the wallpaper, ported from the iRiS
// desktop-widget family and kept deliberately quiet for Ryoku — one form, a
// fill or a hairline outline, painted in the accent (or the widget's pinned
// colour / gradient, applied by the slot). A composition element, not a readout.
Item {
    id: face

    property real underL: Scheme.wallLstar
    property string inkColorA: ""
    property real s: 1

    // dot | ring | diamond | square. ring is always an outline.
    readonly property string kind: Config.shapeKind
    readonly property bool outline: Config.shapeOutline || face.kind === "ring"
    readonly property color mark: Theme.accentOn2(face.underL, face.inkColorA)

    readonly property real dim: Math.round(140 * face.s)
    readonly property real stroke: Math.max(2, Math.round(5 * face.s))
    implicitWidth: face.dim
    implicitHeight: face.dim

    Item {
        anchors.centerIn: parent
        // A diamond is a square turned 45°, so it must shrink to stay inside.
        width: face.kind === "diamond" ? Math.round(face.dim / 1.42) : face.dim
        height: width
        rotation: face.kind === "diamond" ? 45 : 0

        Rectangle {
            anchors.fill: parent
            radius: (face.kind === "dot" || face.kind === "ring") ? width / 2
                : face.kind === "square" ? Math.round(width * 0.26)
                : Math.round(width * 0.12)
            color: face.outline ? "transparent" : face.mark
            border.width: face.outline ? face.stroke : 0
            border.color: face.mark
        }
    }
}
