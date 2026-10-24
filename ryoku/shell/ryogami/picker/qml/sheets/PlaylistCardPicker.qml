import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: card

    property PickerState state: null
    property string wallKey: ""
    property string wallName: ""

    signal closeRequested()

    anchors.fill: parent

    property var lists: []
    property var memberIds: []

    readonly property var _curated: {
        var out = []
        for (var i = 0; i < card.lists.length; ++i)
            if (card.lists[i].kind !== "smart")
                out.push(card.lists[i])
        return out
    }

    function _isMember(id) { return card.memberIds.indexOf(id) >= 0 }

    function _parseMemberIds(res) {
        if (!res)
            return []
        if (Array.isArray(res.ids))
            return res.ids
        if (Array.isArray(res.member_ids))
            return res.member_ids
        if (Array.isArray(res.playlists)) {
            var out = []
            for (var i = 0; i < res.playlists.length; ++i) {
                var p = res.playlists[i]
                if (p.member === true || p.contains === true || p.hasKey === true)
                    out.push(p.id)
            }
            return out
        }
        return []
    }

    function refresh() {
        Daemon.call("playlist.list", {}, function(res, err) {
            if (err) {
                if (card.state)
                    card.state.toast(err.message || I18n.tr("Playlists could not be loaded."), "error")
                return
            }
            card.lists = (res && res.playlists) ? res.playlists : []
        })
        if (card.wallKey.length > 0) {
            Daemon.call("playlist.memberships", { key: card.wallKey }, function(res, err) {
                if (err)
                    return
                card.memberIds = card._parseMemberIds(res)
            })
        }
    }

    function toggle(id) {
        Daemon.call("playlist.toggle", { id: id, key: card.wallKey }, function(res, err) {
            if (err) {
                if (card.state)
                    card.state.toast(err.message || I18n.tr("That change could not be saved."), "error")
                return
            }
            card.refresh()
        })
    }

    function createWith(name) {
        var n = String(name || "").trim()
        if (n.length === 0)
            n = I18n.tr("Playlist %1").arg(card.lists.length + 1)
        Daemon.call("playlist.create", { name: n }, function(res, err) {
            if (err) {
                if (card.state)
                    card.state.toast(err.message || I18n.tr("That playlist could not be created."), "error")
                return
            }
            var id = (res && res.id) ? res.id : 0
            if (id > 0 && card.wallKey.length > 0) {
                Daemon.call("playlist.add", { id: id, key: card.wallKey }, function(r2, e2) {
                    if (e2 && card.state)
                        card.state.toast(e2.message || I18n.tr("That wallpaper could not be added."), "error")
                    card.refresh()
                })
            } else {
                card.refresh()
            }
        })
    }

    onVisibleChanged: if (card.visible) card.refresh()

    Scrim {
        anchors.fill: parent
        alpha: 0.55
        reveal: card.visible ? 1 : 0
        onDismissed: card.closeRequested()
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.max(260 * Theme.scale, Math.min(380 * Theme.scale, parent.width * 0.32))
        height: Math.max(180 * Theme.scale, Math.min(420 * Theme.scale, parent.height * 0.55))
        color: Theme.withAlpha(Theme.surface, 0.99)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.40)
        clip: true

        MouseArea { anchors.fill: parent }

        Column {
            id: head
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14 * Theme.scale
            spacing: 5 * Theme.scale

            RowLayout {
                width: parent.width
                spacing: 8 * Theme.scale

                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Add to playlist")
                    font.family: Theme.display
                    font.pixelSize: Theme.fontLabel
                    color: Theme.surfaceText
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
                FolioAction {
                    label: "\u00d7"
                    minWidth: 30
                    onTriggered: card.closeRequested()
                }
            }
            Text {
                width: parent.width
                visible: card.wallName.length > 0
                text: card.wallName
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBody
                color: Theme.withAlpha(Theme.surfaceText, 0.6)
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
        }

        Column {
            id: foot
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 14 * Theme.scale
            spacing: 6 * Theme.scale

            Text {
                width: parent.width
                text: card._curated.length === 0
                    ? I18n.tr("No playlists exist yet. Name one to create it with this wallpaper already added:")
                    : I18n.tr("Or create another playlist with this wallpaper:")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontSmall
                color: Theme.withAlpha(Theme.surfaceText, 0.44)
                lineHeight: 1.35
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
            RowLayout {
                width: parent.width
                spacing: 6 * Theme.scale

                TextField {
                    id: newField
                    Layout.fillWidth: true
                    variant: "field"
                    placeholder: I18n.tr("New playlist name")
                    onCommitted: (t) => { card.createWith(t); newField.text = "" }
                }
                FolioAction {
                    label: "\uff0b"
                    active: true
                    fixedWidth: 40 * Theme.scale
                    onTriggered: { card.createWith(newField.text); newField.text = "" }
                }
            }
        }

        ListView {
            id: rows
            anchors.top: head.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: foot.top
            anchors.topMargin: 8 * Theme.scale
            anchors.leftMargin: 14 * Theme.scale
            anchors.rightMargin: 14 * Theme.scale
            anchors.bottomMargin: 8 * Theme.scale
            clip: true
            spacing: 5 * Theme.scale
            boundsBehavior: Flickable.StopAtBounds
            model: card._curated

            delegate: FolioAction {
                required property var modelData
                width: ListView.view.width
                fixedWidth: ListView.view.width
                active: card._isMember(modelData.id)
                label: (card._isMember(modelData.id) ? "\u2713 " : "")
                    + ((modelData.name && modelData.name.length) ? modelData.name : I18n.tr("(unnamed)"))
                    + I18n.tr(" \u00b7 ID %1").arg(modelData.id)
                onTriggered: card.toggle(modelData.id)
            }
        }
    }

    Keys.onEscapePressed: card.closeRequested()
}
