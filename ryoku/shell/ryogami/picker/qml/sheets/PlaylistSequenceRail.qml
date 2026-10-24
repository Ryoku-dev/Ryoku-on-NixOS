import QtQuick
import Ryoku.Ui.Singletons

Rectangle {
    id: rail

    property var members: []
    property bool smart: false
    property int pid: -1
    property real reveal: 1

    signal moveRequested(string key, int delta)
    signal removeRequested(string key)

    color: Theme.withAlpha(Theme.surfaceContainer, 0.14)

    readonly property int _count: rail.members ? rail.members.length : 0

    Column {
        id: heading
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 30 * Theme.scale
        anchors.leftMargin: 14 * Theme.scale
        anchors.rightMargin: 14 * Theme.scale
        spacing: 8 * Theme.scale

        Item {
            width: parent.width
            height: title.implicitHeight

            Text {
                id: title
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: rail.smart ? I18n.tr("Matching wallpapers") : I18n.tr("Playback order")
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.7)
                renderType: Text.NativeRendering
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: rail._count < 10 ? "0" + rail._count : String(rail._count)
                font.family: Theme.display
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.44)
                renderType: Text.NativeRendering
            }
        }

        Text {
            width: parent.width
            text: rail.smart
                ? I18n.tr("These wallpapers match the filter and refresh as your library changes.")
                : I18n.tr("Wallpapers play from top to bottom. Use the arrows to change the order.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontMini
            color: Theme.withAlpha(Theme.surfaceText, 0.48)
            lineHeight: 1.4
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }

        FolioRule {
            width: parent.width
            alpha: 0.58
        }
    }

    ListView {
        id: list
        anchors.top: heading.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 12 * Theme.scale
        anchors.leftMargin: 14 * Theme.scale
        anchors.rightMargin: 14 * Theme.scale
        anchors.bottomMargin: 24 * Theme.scale
        clip: true
        visible: rail._count > 0
        boundsBehavior: Flickable.StopAtBounds
        model: rail.members

        delegate: PlaylistMemberRow {
            required property var modelData
            required property int index
            width: ListView.view.width
            entry: modelData
            ordinal: index + 1
            total: rail._count
            smart: rail.smart
            onMoveUp: rail.moveRequested(modelData.key, -1)
            onMoveDown: rail.moveRequested(modelData.key, 1)
            onRemoveRequested: rail.removeRequested(modelData.key)
        }
    }

    Column {
        anchors.top: heading.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 20 * Theme.scale
        anchors.leftMargin: 14 * Theme.scale
        anchors.rightMargin: 14 * Theme.scale
        spacing: 6 * Theme.scale
        visible: rail._count === 0

        Text {
            width: parent.width
            text: rail.smart
                ? I18n.tr("No wallpapers match this filter yet.")
                : I18n.tr("This playlist is empty. Open a wallpaper card and choose Playlist to add it.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBody
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }
        Text {
            width: parent.width
            text: rail.smart
                ? I18n.tr("Adjust the source or colours on the left to widen the match.")
                : I18n.tr("You can also use Add wallpapers under Playlist details.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontFine
            color: Theme.withAlpha(Theme.surfaceText, 0.46)
            lineHeight: 1.4
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }
    }
}
