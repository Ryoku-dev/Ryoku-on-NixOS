import QtQuick
import Ryoku.Ui.Singletons

Rectangle {
    id: masthead

    property string wordmark: I18n.tr("Ryogami")
    property string breadcrumb: ""
    property real reveal: 1

    signal closeRequested()

    implicitHeight: Theme.folioMastheadHeight * Math.max(1, Theme.scale)
    color: Theme.withAlpha(Theme.background, 0.94)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outline, 0.5)

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 20 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        text: masthead.wordmark
        font.family: Theme.display
        font.pixelSize: Theme.fontHead
        color: Theme.surfaceText
        renderType: Text.NativeRendering
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 20 * Theme.scale
        anchors.verticalCenter: parent.verticalCenter
        spacing: 13 * Theme.scale

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: masthead.breadcrumb.length > 0
            text: masthead.breadcrumb
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontSmall
            color: Theme.withAlpha(Theme.surfaceText, 0.54)
            renderType: Text.NativeRendering
        }

        FolioAction {
            anchors.verticalCenter: parent.verticalCenter
            label: "\u00d7"
            minWidth: 30
            onTriggered: masthead.closeRequested()
        }
    }
}
