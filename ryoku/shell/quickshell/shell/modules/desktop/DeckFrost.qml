import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    property rect focusRect
    property real floorAlpha: 0
    property real strength: 0

    visible: opacity > 0.001
    opacity: Math.max(0, Math.min(1, root.strength))
    Behavior on opacity {
        NumberAnimation {
            duration: Tokens.dur(180)
            easing.type: Easing.OutCubic
        }
    }

    ShaderEffect {
        id: haze
        anchors.fill: parent
        visible: status !== ShaderEffect.Error
        blending: true

        property vector2d surfaceSize: Qt.vector2d(width, height)
        property vector4d focusBounds: Qt.vector4d(root.focusRect.x,
            root.focusRect.y, root.focusRect.width, root.focusRect.height)
        property real floorAlpha: root.floorAlpha

        fragmentShader: Qt.resolvedUrl("deck-frost.frag.qsb")
    }

    Rectangle {
        anchors.fill: parent
        visible: haze.status === ShaderEffect.Error
        color: "black"
    }
}
