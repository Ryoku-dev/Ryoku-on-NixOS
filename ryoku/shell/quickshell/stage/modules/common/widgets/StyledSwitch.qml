import stage.modules.common
import QtQuick
import QtQuick.Controls

// The compatibility switch follows Ryoku.Ui Sw while preserving the island's
// checked property and caller-facing colour overrides.
Switch {
    id: root
    hoverEnabled: true

    property real sizeScale: 1
    implicitWidth: 54 * root.sizeScale
    implicitHeight: 24 * root.sizeScale

    property color activeColor: Appearance.colors.colLayer1Active
    property color inactiveColor: Appearance.colors.colLayer1Hover
    property color activeThumbColor: Appearance.colors.colOnSurface
    property color inactiveThumbColor: Appearance.colors.colOnSurfaceVariant

    readonly property real inset: 3 * root.sizeScale
    readonly property real knobSize: 17 * root.sizeScale
    readonly property bool isPressed: root.pressed || root.down

    scale: root.isPressed && root.enabled ? 0.96 : 1
    Behavior on scale {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSnap.duration
            easing.type: Appearance.animation.elementMoveSnap.type
        }
    }

    PointingHandInteraction {}

    background: Rectangle {
        width: root.width
        height: root.height
        radius: Appearance.rounding.small
        color: root.checked ? root.activeColor : root.inactiveColor
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Appearance.colors.colOnSurface
            : root.hovered ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    indicator: Rectangle {
        width: root.knobSize
        height: root.knobSize
        radius: Appearance.rounding.small
        y: root.inset
        x: root.checked ? root.width - width - root.inset : root.inset
        color: root.checked ? root.activeThumbColor : root.inactiveThumbColor

        Behavior on x {
            NumberAnimation {
                duration: Appearance.animation.elementMoveSnap.duration
                easing.type: Appearance.animation.elementMoveSnap.type
            }
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
