import QtQuick

// One workspace in the Spaces overview: its mark, its name and its window count.
Rectangle {
    id: root

    required property var pal
    property real k: 1
    property string mark: ""
    property string name: ""
    property int count: 0
    property bool selected: false

    signal activated()

    function px(v) { return Math.round(v * root.k) }

    implicitWidth: px(76)
    implicitHeight: px(78)
    activeFocusOnTab: true
    radius: px(pal.radiusM)
    color: selected ? pal.sealTint : (area.pressed ? pal.press : (area.containsMouse ? pal.hover : pal.raised))
    border.width: 1
    border.color: activeFocus ? pal.seal : (selected ? pal.sealEdge : (area.containsMouse ? pal.lineStrong : pal.lineSoft))
    Behavior on color { enabled: pal.animate; ColorAnimation { duration: 110 } }

    Column {
        anchors.centerIn: parent
        spacing: root.px(3)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.mark
            color: root.selected ? root.pal.seal : root.pal.ink
            font.family: root.pal.jp
            font.pixelSize: root.px(22)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.name
            color: root.pal.ink
            font.family: root.pal.mono
            font.pixelSize: root.px(9.5)
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.count === 0 ? "empty" : (root.count === 1 ? "1 window" : root.count + " windows")
            color: root.pal.inkMuted
            font.family: root.pal.text
            font.pixelSize: root.px(9)
        }
    }

    Keys.onReturnPressed: root.activated()
    Keys.onEnterPressed: root.activated()
    Keys.onSpacePressed: root.activated()

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
