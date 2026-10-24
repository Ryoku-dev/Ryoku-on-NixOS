import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    property int step: 1
    property string title: ""
    property string description: ""
    property bool done: false
    property bool current: false
    property bool last: false
    default property alias detail: detail.data

    implicitHeight: Math.max(Tokens.s6, body.implicitHeight) + (last ? 0 : Tokens.s4)
    opacity: current ? 1 : done ? 0.82 : 0.48
    Behavior on opacity {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
    }

    Item {
        id: marker
        anchors.left: parent.left
        anchors.top: parent.top
        width: Tokens.s6
        height: root.height

        Rectangle {
            id: disc
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Tokens.s6
            height: width
            radius: width / 2
            color: root.current || root.done ? Tokens.bone : "transparent"
            border.width: Tokens.border
            border.color: root.current || root.done ? Tokens.bone : Tokens.lineStrong
            scale: root.current ? 1 : 0.9
            Behavior on color {
                enabled: !Tokens.reduceMotion
                ColorAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
            }
            Text {
                anchors.centerIn: parent
                text: root.done ? "✓" : String(root.step)
                color: root.current || root.done ? Tokens.inkOnBone : Tokens.inkMuted
                font.family: Tokens.mono
                font.pixelSize: Tokens.fSmall
                font.weight: Font.DemiBold
            }
        }

        Rectangle {
            visible: !root.last
            anchors.top: disc.bottom
            anchors.topMargin: Tokens.s1
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Tokens.border
            color: root.done ? Tokens.lineStrong : Tokens.lineSoft
        }
    }

    Column {
        id: body
        anchors.left: marker.right
        anchors.leftMargin: Tokens.s4
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Tokens.s2

        Text {
            width: parent.width
            text: root.title
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fRow
            font.weight: root.current ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
        }
        Text {
            visible: root.current
            width: parent.width
            text: root.description
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }
        Column {
            id: detail
            visible: root.current
            width: parent.width
            spacing: Tokens.s2
            opacity: root.current ? 1 : 0
            Behavior on opacity {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
            }
        }
    }
}
