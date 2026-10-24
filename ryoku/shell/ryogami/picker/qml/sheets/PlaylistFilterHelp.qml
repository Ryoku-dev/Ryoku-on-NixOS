import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: help

    signal closeRequested()

    anchors.fill: parent

    readonly property var _entries: [
        I18n.tr("Separate filters with spaces. Every filter must match. Names and paths cannot contain spaces."),
        I18n.tr("all / favourites"),
        I18n.tr("folder:nature/forest"),
        I18n.tr("type:image / type:video / type:we"),
        I18n.tr("tag:cat,night / tag:cat|dog,-anime"),
        I18n.tr("color:blue,cyan / colour:gray"),
        I18n.tr("ratio:portrait / ratio:landscape / ratio:square"),
        I18n.tr("width:>=1920"),
        I18n.tr("height:>=1080"),
        I18n.tr("res:>=1920x1080"),
        I18n.tr("Comparisons: >=, <=, >, <, ="),
        I18n.tr("Example: favourites type:video ratio:landscape color:blue")
    ]

    Scrim {
        anchors.fill: parent
        alpha: 0.68
        reveal: help.visible ? 1 : 0
        onDismissed: help.closeRequested()
    }

    ChamferPanel {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 60 * Theme.scale, 560 * Theme.scale)
        height: Math.min(parent.height - 60 * Theme.scale, 560 * Theme.scale)
        reveal: help.visible ? 1 : 0

        MouseArea { anchors.fill: parent }

        Item {
            id: headerRow
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 20 * Theme.scale
            height: headerText.implicitHeight

            Text {
                id: headerText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Filter reference")
                font.family: Theme.display
                font.pixelSize: Theme.fontHead
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }
            FolioAction {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                label: "\u00d7"
                minWidth: 30
                onTriggered: help.closeRequested()
            }
        }

        Flickable {
            anchors.top: headerRow.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 20 * Theme.scale
            anchors.topMargin: 16 * Theme.scale
            clip: true
            contentWidth: width
            contentHeight: entries.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: entries
                width: parent.width
                spacing: 16 * Theme.scale

                Repeater {
                    model: help._entries
                    delegate: Text {
                        required property string modelData
                        width: entries.width
                        text: modelData
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontBody
                        color: Theme.surfaceText
                        lineHeight: 1.35
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: help.closeRequested()
}
