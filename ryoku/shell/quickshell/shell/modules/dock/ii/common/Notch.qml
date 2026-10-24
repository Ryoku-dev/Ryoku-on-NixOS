import QtQuick
import QtQuick.Shapes
import ".."

Item {
    id: root

    property real bodyWidth: 200
    property real bodyHeight: 32
    property real topRadius: 6
    property real bottomRadius: 14
    property color fillColor: Appearance.colors.colLayer0
    property bool disableBehaviors: false
    property real bleedTop: 0

    implicitWidth: bodyWidth
    implicitHeight: bodyHeight

    Shape {
        id: shape
        anchors.fill: parent
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: path
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.fillColor
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.FlatCap

            readonly property real w: root.width
            readonly property real h: root.height
            readonly property real tr: Math.max(0, Math.min(root.topRadius, w / 2))
            readonly property real br: Math.max(0, Math.min(root.bottomRadius, (w - 2 * tr) / 2, h))

            startX: 0
            startY: 0

            PathCubic {
                x: path.tr
                y: path.tr
                control1X: path.tr * 0.5523
                control1Y: 0
                control2X: path.tr
                control2Y: path.tr * 0.4477
            }
            PathLine {
                x: path.tr
                y: path.h - path.br
            }
            PathCubic {
                x: path.tr + path.br
                y: path.h
                control1X: path.tr
                control1Y: path.h - path.br * 0.4477
                control2X: path.tr + path.br * 0.4477
                control2Y: path.h
            }
            PathLine {
                x: path.w - path.tr - path.br
                y: path.h
            }
            PathCubic {
                x: path.w - path.tr
                y: path.h - path.br
                control1X: path.w - path.tr - path.br * 0.4477
                control1Y: path.h
                control2X: path.w - path.tr
                control2Y: path.h - path.br * 0.4477
            }
            PathLine {
                x: path.w - path.tr
                y: path.tr
            }
            PathCubic {
                x: path.w
                y: 0
                control1X: path.w - path.tr
                control1Y: path.tr * 0.4477
                control2X: path.w - path.tr * 0.5523
                control2Y: 0
            }
            PathLine {
                x: 0
                y: 0
            }
        }
    }

    Behavior on bodyWidth     { enabled: !root.disableBehaviors; NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on bodyHeight    { enabled: !root.disableBehaviors; NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on topRadius     { enabled: !root.disableBehaviors; NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on bottomRadius  { enabled: !root.disableBehaviors; NumberAnimation { duration: Appearance.animation.elementMove.duration; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve } }
    Behavior on fillColor     { enabled: !root.disableBehaviors; ColorAnimation   { duration: Appearance.animation.elementMoveFast.duration; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
}
