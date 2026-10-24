import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: card

    // A theme.previews entry: { backend, key, value, label, palette }.
    property var preview: ({})
    property bool active: false
    property real cardWidth: 202 * Theme.scale

    signal picked()

    width: card.cardWidth
    implicitWidth: card.cardWidth
    implicitHeight: body.implicitHeight + 2 * 8 * Theme.scale

    readonly property bool hovered: hoverArea.containsMouse

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: card.active ? Theme.withAlpha(Theme.surfaceText, 0.09)
            : card.hovered ? Theme.withAlpha(Theme.surfaceText, 0.05)
            : "transparent"
        border.width: card.active ? 2 : 1
        border.color: card.active ? Theme.withAlpha(Theme.surfaceText, 0.7)
            : card.hovered ? Theme.withAlpha(Theme.surfaceText, 0.24)
            : Theme.withAlpha(Theme.outline, 0.4)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    }

    Column {
        id: body
        anchors.fill: parent
        anchors.margins: 8 * Theme.scale
        spacing: 7 * Theme.scale

        ThemeSpecimen {
            width: parent.width
            palette: (card.preview && card.preview.palette) ? card.preview.palette : ({})
        }

        Row {
            width: parent.width
            spacing: 6 * Theme.scale
            height: Math.max(label.implicitHeight, status.implicitHeight)

            Text {
                id: label
                width: parent.width - status.implicitWidth - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: (card.preview && card.preview.label) ? card.preview.label : ""
                elide: Text.ElideRight
                font.family: Theme.sans
                font.weight: card.active ? Font.DemiBold : Font.Medium
                font.pixelSize: Theme.fontBase
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }

            Text {
                id: status
                anchors.verticalCenter: parent.verticalCenter
                text: card.active ? I18n.tr("Selected") : I18n.tr("Preview")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontMicro
                color: Theme.withAlpha(Theme.surfaceText, 0.68)
                renderType: Text.NativeRendering
            }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.picked()
    }
}
