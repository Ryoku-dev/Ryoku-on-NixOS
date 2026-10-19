import QtQuick
import QtQuick.Shapes
import shell.services

// A card body welded onto a bar's bottom edge: the item's rect is the body, and
// two concave fillets flare out of its top corners into the bar above it. The
// tuck runs a row under the bar's edge so no seam line shows at fractional
// scales.
Shape {
    id: root

    property real fillet: 0
    property real radius: 0
    property real tuck: 1
    property string role: "surface"

    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        id: path

        readonly property real f: Math.max(0, root.fillet)
        readonly property real w: root.width
        readonly property real h: root.height
        readonly property real r: Math.max(0, Math.min(root.radius, path.w / 2, path.h))

        fillColor: Theme[root.role] !== undefined ? Theme[root.role] : Theme.surface
        strokeColor: "transparent"
        strokeWidth: -1

        startX: -path.f
        startY: -root.tuck

        PathLine {
            x: path.w + path.f
            y: -root.tuck
        }
        PathLine {
            x: path.w + path.f
            y: 0
        }
        PathArc {
            x: path.w
            y: path.f
            radiusX: path.f
            radiusY: path.f
            direction: PathArc.Counterclockwise
        }
        PathLine {
            x: path.w
            y: path.h - path.r
        }
        PathArc {
            x: path.w - path.r
            y: path.h
            radiusX: path.r
            radiusY: path.r
            direction: PathArc.Clockwise
        }
        PathLine {
            x: path.r
            y: path.h
        }
        PathArc {
            x: 0
            y: path.h - path.r
            radiusX: path.r
            radiusY: path.r
            direction: PathArc.Clockwise
        }
        PathLine {
            x: 0
            y: path.f
        }
        PathArc {
            x: -path.f
            y: 0
            radiusX: path.f
            radiusY: path.f
            direction: PathArc.Counterclockwise
        }
        PathLine {
            x: -path.f
            y: -root.tuck
        }
    }
}
