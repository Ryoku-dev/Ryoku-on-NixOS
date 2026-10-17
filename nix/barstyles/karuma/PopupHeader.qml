import QtQuick

// Seal badge, title and eyebrow, with an optional close button.
Item {
    id: root

    required property var pal
    property real k: 1
    property string glyph: ""
    property string title: ""
    property string eyebrow: ""
    property bool closable: true

    signal closeClicked()

    function px(v) { return Math.round(v * root.k) }

    width: parent ? parent.width : px(300)
    implicitHeight: px(38)
    height: implicitHeight

    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: root.px(36)
        height: width
        radius: root.px(root.pal.radiusM)
        color: root.pal.seal
        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: root.pal.onSeal
            font.family: root.pal.jp
            font.pixelSize: root.px(19)
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: root.px(12)
        anchors.right: closeBtn.visible ? closeBtn.left : parent.right
        anchors.rightMargin: root.px(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.px(1)
        Text {
            width: parent.width
            text: root.title
            color: root.pal.ink
            font.family: root.pal.display
            font.pixelSize: root.px(18)
            elide: Text.ElideRight
        }
        Eyebrow { width: parent.width; pal: root.pal; k: root.k; text: root.eyebrow }
    }

    Rectangle {
        id: closeBtn
        visible: root.closable
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.px(30)
        height: width
        radius: root.px(root.pal.radiusM)
        color: closeArea.pressed ? root.pal.press : (closeArea.containsMouse ? root.pal.hover : "transparent")
        border.width: 1
        border.color: closeArea.containsMouse ? root.pal.line : root.pal.lineSoft
        Behavior on color { enabled: root.pal.animate; ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "×"
            color: closeArea.containsMouse ? root.pal.ink : root.pal.inkMuted
            font.family: root.pal.mono
            font.pixelSize: root.px(17)
        }
        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeClicked()
        }
    }
}
