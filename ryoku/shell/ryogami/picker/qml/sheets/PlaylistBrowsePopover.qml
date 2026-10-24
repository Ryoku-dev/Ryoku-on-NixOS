import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: popover

    property PickerState state: null
    property int pid: -1
    property string playlistName: ""

    signal closeRequested()

    anchors.fill: parent

    LibraryView {
        id: browseView
        collection: "wallpapers"
    }

    Scrim {
        anchors.fill: parent
        alpha: 0.68
        reveal: popover.visible ? 1 : 0
        onDismissed: popover.closeRequested()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 60 * Theme.scale, 1000 * Theme.scale)
        height: Math.min(parent.height - 60 * Theme.scale, 720 * Theme.scale)
        color: Theme.withAlpha(Theme.surface, 0.99)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.58)
        clip: true

        // Swallows clicks so the backdrop dismiss does not fire.
        MouseArea { anchors.fill: parent }

        RowLayout {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 18 * Theme.scale
            spacing: 10 * Theme.scale

            Text {
                text: I18n.tr("Add wallpapers")
                font.family: Theme.display
                font.pixelSize: Theme.fontHead
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }
            Text {
                Layout.fillWidth: true
                visible: popover.playlistName.length > 0
                text: popover.playlistName
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBody
                color: Theme.withAlpha(Theme.surfaceText, 0.6)
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
            Item { Layout.fillWidth: true; visible: popover.playlistName.length === 0 }
            FolioAction {
                label: "\u00d7"
                minWidth: 30
                onTriggered: popover.closeRequested()
            }
        }

        TextField {
            id: search
            anchors.top: header.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 12 * Theme.scale
            anchors.leftMargin: 18 * Theme.scale
            anchors.rightMargin: 18 * Theme.scale
            variant: "ghost"
            glyph: "\uf002"
            placeholder: I18n.tr("Search wallpapers")
            onEdited: (t) => browseView.query = t
        }

        Item {
            anchors.top: search.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: 12 * Theme.scale
            anchors.leftMargin: 18 * Theme.scale
            anchors.rightMargin: 18 * Theme.scale
            anchors.bottomMargin: 18 * Theme.scale

            CardField {
                id: field
                anchors.fill: parent
                source: browseView
                settings: Settings
                mode: "wall"
                interactive: true
                active: popover.visible && browseView.count > 0
                visible: browseView.count > 0
                palette: ({
                    primary: Theme.primary,
                    accent: Theme.primary,
                    surface: Theme.surface,
                    surfaceVariant: Theme.surfaceVariant,
                    outline: Theme.outline,
                    text: Theme.surfaceText,
                    shadow: "black"
                })

                onActivated: function(row) {
                    var e = browseView.get(row)
                    if (!e || !e.key || popover.pid <= 0)
                        return
                    Daemon.call("playlist.add", { id: popover.pid, key: e.key }, function(res, err) {
                        if (err) {
                            if (popover.state)
                                popover.state.toast(err.message || I18n.tr("That wallpaper could not be added."), "error")
                            return
                        }
                        if (popover.state)
                            popover.state.toast(I18n.tr("Added to playlist"), "success")
                    })
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 40 * Theme.scale
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: browseView.count === 0
                text: browseView.query && browseView.query.length > 0
                    ? I18n.tr("No wallpapers match this search.")
                    : I18n.tr("No wallpapers in your library yet.")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontLabel
                color: Theme.withAlpha(Theme.surfaceText, 0.4)
                renderType: Text.NativeRendering
            }
        }
    }

    Keys.onEscapePressed: popover.closeRequested()
}
