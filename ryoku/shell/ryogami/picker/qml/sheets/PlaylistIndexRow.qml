import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property int pid: 0
    property string name: ""
    property string detail: ""
    property bool playing: false
    property bool selected: false

    signal clicked()

    implicitHeight: Math.max(mid.implicitHeight, marker.implicitHeight) + 18 * Theme.scale

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: row.selected ? Theme.withAlpha(Theme.surfaceText, 0.06)
             : hover.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.09)
             : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2 * Theme.scale
        height: row.selected ? parent.height - 12 * Theme.scale : 0
        radius: width
        color: Theme.surfaceText
        Behavior on height { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutBack } }
    }

    Text {
        id: idLabel
        anchors.left: parent.left
        anchors.leftMargin: 10 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        text: I18n.tr("ID %1").arg(row.pid)
        font.family: Theme.display
        font.pixelSize: Theme.fontFine
        color: (row.selected || row.playing) ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.5)
        renderType: Text.NativeRendering
    }

    Text {
        id: marker
        anchors.right: parent.right
        anchors.rightMargin: 10 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        text: row.playing ? "\u25cf" : "\u25cb"
        font.family: Theme.sans
        font.pixelSize: Theme.fontFine
        color: row.playing ? Theme.surfaceText
             : (row.selected || hover.containsMouse) ? Theme.withAlpha(Theme.surfaceText, 0.55)
             : Theme.withAlpha(Theme.surfaceText, 0.3)
        renderType: Text.NativeRendering
    }

    Column {
        id: mid
        anchors.left: idLabel.right
        anchors.leftMargin: 9 * Theme.scale
        anchors.right: marker.left
        anchors.rightMargin: 9 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3 * Theme.scale

        Text {
            width: parent.width
            text: row.name
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontBody
            color: Theme.surfaceText
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
        Text {
            width: parent.width
            text: row.detail
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontTiny
            color: row.playing ? Theme.withAlpha(Theme.surfaceText, 0.7) : Theme.withAlpha(Theme.surfaceText, 0.44)
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.clicked()
    }
}
