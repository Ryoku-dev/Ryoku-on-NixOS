import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: chip

    signal triggered()

    implicitHeight: line.implicitHeight + 4 * Theme.scale
    implicitWidth: line.implicitWidth + 8 * Theme.scale

    readonly property bool hovered: area.containsMouse

    Row {
        id: line
        anchors.centerIn: parent
        spacing: 4 * Theme.scale

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u21ba"
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontFine
            color: Theme.withAlpha(Theme.surfaceText, chip.hovered ? 1 : 0.5)
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Reset")
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontFine
            color: Theme.withAlpha(Theme.surfaceText, chip.hovered ? 1 : 0.5)
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.triggered()
    }
}
