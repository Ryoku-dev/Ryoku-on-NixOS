import QtQuick
import Quickshell.Widgets

Item {
    id: root

    property url source: ""
    property real size: 112
    property bool round: false
    property bool spinning: false
    property real _rotation: 0

    implicitWidth: size
    implicitHeight: size

    onSpinningChanged: {
        if (!spinning)
            _rotation = 0;
    }
    onVisibleChanged: {
        if (!visible)
            _rotation = 0;
    }

    ClippingRectangle {
        id: artwork
        anchors.fill: parent
        radius: root.round ? width / 2 : Style.radius
        color: Style.tint5
        rotation: root._rotation

        Image {
            id: image
            readonly property int texels: Math.max(1,
                Math.round(root.size * Screen.devicePixelRatio * 2))
            anchors.fill: parent
            source: root.source
            sourceSize: Qt.size(texels, texels)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            visible: status === Image.Ready
        }

        Glyph {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            name: "music_note"
            size: Math.max(Style.icon, root.size * 0.34)
            tone: "dim"
        }
    }

    NumberAnimation on _rotation {
        from: 0
        to: 360
        duration: 8000
        loops: Animation.Infinite
        running: root.spinning && root.visible && image.status === Image.Ready
            && !Style.still
    }
}
