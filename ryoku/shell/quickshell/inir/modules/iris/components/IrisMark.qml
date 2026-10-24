import QtQuick
import inir.modules.iris.style

// Shima's mark: an island resting on the horizon.
Item {
    id: root
    property real implicitSize: 22 * IrisStyle.density
    property color color: IrisStyle.accent
    property bool orbiting: false
    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Rectangle {
        id: island
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.implicitSize * 0.30
        width: root.implicitSize * 0.74
        height: root.implicitSize * 0.30
        radius: height / 2
        color: root.color

        SequentialAnimation on y {
            running: root.orbiting && IrisStyle.motionEnabled
            loops: Animation.Infinite
            NumberAnimation { to: root.implicitSize * 0.24; duration: 1400; easing.type: Easing.InOutSine }
            NumberAnimation { to: root.implicitSize * 0.30; duration: 1400; easing.type: Easing.InOutSine }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.implicitSize * 0.72
        width: root.implicitSize * 0.92
        height: Math.max(1, root.implicitSize * 0.08)
        radius: height / 2
        color: IrisStyle.secondaryAccent
    }
}
