import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state
    property var args: ({})
    property bool shown: false

    signal closeRequested()

    anchors.fill: parent
    focus: root.shown

    readonly property bool cardMode: !!root.args
        && (root.args.cardPicker === true
            || (root.args.addKey !== undefined && root.args.addKey !== null && String(root.args.addKey).length > 0))
    readonly property string cardKey: root.args ? String(root.args.key || root.args.addKey || "") : ""
    readonly property string cardName: root.args ? String(root.args.name || root.args.addName || "") : ""

    property real _reveal: shown ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: _reveal > 0.001

    property var playlists: []
    property var _assignments: []
    property var members: []
    property int selectedId: -1
    property bool _loaded: false
    property int _selectAfterCreate: -1
    property bool _browseOpen: false
    property bool _filterHelpOpen: false

    readonly property var selectedDef: {
        for (var i = 0; i < root.playlists.length; ++i)
            if (root.playlists[i].id === root.selectedId)
                return root.playlists[i]
        return null
    }
    readonly property bool smart: root.selectedDef !== null && root.selectedDef.kind === "smart"
    readonly property string _defName: root.selectedDef ? String(root.selectedDef.name || "") : ""
    readonly property string _defSource: root.selectedDef ? String(root.selectedDef.source || "") : ""
    readonly property string _defKind: root.selectedDef ? String(root.selectedDef.kind || "curated") : "curated"
    readonly property string _defOrder: root.selectedDef ? String(root.selectedDef.order || "added") : "added"
    readonly property int _defDwell: root.selectedDef ? (root.selectedDef.dwell || 600) : 600
    readonly property int _defCount: root.selectedDef ? (root.selectedDef.count || 0) : 0

    readonly property string _crumbName: root.selectedDef
        ? (root._defName.length > 0 ? root._defName : I18n.tr("(unnamed)"))
        : I18n.tr("Library")
    readonly property string _displayName: root.selectedDef
        ? (root._defName.length > 0 ? root._defName : I18n.tr("(unnamed)"))
        : ""

    readonly property var _outputNames: {
        var out = []
        var o = Library.outputs
        for (var i = 0; i < o.length; ++i)
            out.push(o[i].name)
        return out
    }

    function _pad2(n) { return n < 10 ? "0" + n : String(n) }

    function assignedId(output) {
        var a = root._assignments
        for (var i = 0; i < a.length; ++i)
            if (a[i].output === output)
                return a[i].id
        return 0
    }
    function allOn(id) { return root.assignedId("*") === id }
    function isPlaying(id) {
        var a = root._assignments
        for (var i = 0; i < a.length; ++i)
            if (a[i].id === id)
                return true
        return false
    }
    function activeOutputsFor(id) {
        if (root.allOn(id))
            return root._outputNames
        var a = root._assignments
        var out = []
        for (var i = 0; i < a.length; ++i)
            if (a[i].id === id && a[i].output !== "*")
                out.push(a[i].output)
        return out
    }
    function assignmentCount() { return root._assignments.length }
    function anyActive() { return root._assignments.length > 0 }

    function _indexDetail(def) {
        var kind = def.kind === "smart" ? I18n.tr("Filtered") : I18n.tr("Manual")
        if (root.isPlaying(def.id)) {
            var outs = root.allOn(def.id) ? "*" : root.activeOutputsFor(def.id).join(", ")
            return I18n.tr("%1 \u00b7 active on %2").arg(kind).arg(outs)
        }
        var n = def.count || 0
        return kind + "  \u00b7  " + (n === 1 ? I18n.tr("%1 wallpaper").arg(n) : I18n.tr("%1 wallpapers").arg(n))
    }

    readonly property string _stateCopy: {
        if (!root.selectedDef)
            return ""
        var id = root.selectedDef.id
        if (root.isPlaying(id)) {
            var outs = root.allOn(id) ? "*" : root.activeOutputsFor(id).join("  +  ")
            return I18n.tr("Active / %1").arg(outs)
        }
        if (root.smart && root._defCount === 0)
            return I18n.tr("Filter ready")
        return I18n.tr("%1 wallpapers ready").arg(root._pad2(root._defCount))
    }
    readonly property string _routingState: {
        if (!root.selectedDef)
            return ""
        var id = root.selectedDef.id
        if (root.allOn(id))
            return I18n.tr("Every connected display")
        if (root.isPlaying(id))
            return I18n.tr("Active assignment")
        return I18n.tr("No active assignment")
    }

    function refreshList() {
        Daemon.call("playlist.list", {}, function(res, err) {
            if (err) {
                root.state.toast(err.message || I18n.tr("Playlists could not be loaded."), "error")
                return
            }
            root.playlists = (res && res.playlists) ? res.playlists : []
            root._assignments = (res && res.assignments) ? res.assignments : []
            root._loaded = true
            if (root._selectAfterCreate > 0) {
                for (var i = 0; i < root.playlists.length; ++i) {
                    if (root.playlists[i].id === root._selectAfterCreate) {
                        root.selectPlaylist(root._selectAfterCreate)
                        break
                    }
                }
                root._selectAfterCreate = -1
            }
            if (root.selectedId > 0) {
                var exists = false
                for (var j = 0; j < root.playlists.length; ++j)
                    if (root.playlists[j].id === root.selectedId)
                        exists = true
                if (exists) {
                    root._syncEditors()
                    root.refreshMembers()
                }
                else {
                    root.selectedId = -1
                    root.members = []
                }
            }
        })
    }
    function selectPlaylist(id) {
        root.selectedId = id
        root._syncEditors()
        root.refreshMembers()
    }
    // Never clobbers a field the user is typing in.
    function _syncEditors() {
        if (!nameField.editing)
            nameField.text = root._defName
        if (!filterField.editing)
            filterField.text = root._defSource
        if (!dwellField.editing)
            dwellField.text = String(root._defDwell)
    }
    function refreshMembers() {
        if (root.selectedId <= 0) {
            root.members = []
            return
        }
        var want = root.selectedId
        Daemon.call("playlist.members", { id: want }, function(res, err) {
            if (want !== root.selectedId)
                return
            if (err) {
                root.state.toast(err.message || I18n.tr("Members could not be loaded."), "error")
                return
            }
            root.members = (res && res.members) ? res.members : []
        })
    }

    function _fire(method, params) {
        Daemon.call(method, params, function(res, err) {
            if (err)
                root.state.toast(err.message || I18n.tr("That change could not be saved."), "error")
        })
    }
    function updateField(id, field, value) {
        if (id <= 0)
            return
        root._fire("playlist.update", { id: id, field: field, value: String(value) })
    }
    function createPlaylist(name) {
        var n = String(name || "").trim()
        if (n.length === 0)
            return
        Daemon.call("playlist.create", { name: n }, function(res, err) {
            if (err) {
                root.state.toast(err.message || I18n.tr("That playlist could not be created."), "error")
                return
            }
            root._selectAfterCreate = (res && res.id) ? res.id : -1
            root.refreshList()
        })
    }
    function deletePlaylist(id) {
        if (id <= 0)
            return
        Daemon.call("playlist.delete", { id: id }, function(res, err) {
            if (err) {
                root.state.toast(err.message || I18n.tr("That playlist could not be deleted."), "error")
                return
            }
            root.selectedId = -1
            root.members = []
            root.refreshList()
        })
    }
    function addMember(id, key) { if (id > 0 && key) root._fire("playlist.add", { id: id, key: key }) }
    function removeMember(id, key) { if (id > 0 && key) root._fire("playlist.remove", { id: id, key: key }) }
    function moveMember(id, key, delta) { if (id > 0 && key) root._fire("playlist.move", { id: id, key: key, delta: delta }) }
    function assign(output, id) { root._fire("playlist.assign", { output: output, id: id }) }
    function stopPlaylist(id) { root._fire("playlist.stop", { id: id }) }
    function playNow(id) { if (id > 0) root._fire("playlist.play_now", { id: id }) }

    function _dwellValue(text) {
        var n = parseInt(String(text).trim())
        if (isNaN(n))
            n = 600
        if (n < 1)
            n = 1
        return String(n)
    }

    // Turning one output off while the wildcard owns this list expands to every other output first.
    function toggleOutput(output, id) {
        if (id <= 0)
            return
        if (root.assignedId("*") === id) {
            var outs = root._outputNames
            for (var i = 0; i < outs.length; ++i)
                if (outs[i] !== output)
                    root.assign(outs[i], id)
            root.assign("*", 0)
        } else {
            var own = root.assignedId(output) === id
            root.assign(output, own ? 0 : id)
        }
    }
    function toggleAll(id) {
        if (id <= 0)
            return
        var all = root.assignedId("*") === id
        var outs = root._outputNames
        for (var i = 0; i < outs.length; ++i)
            root.assign(outs[i], 0)
        root.assign("*", all ? 0 : id)
    }

    Component.onCompleted: {
        Library.refreshOutputs()
        root.refreshList()
    }
    onShownChanged: {
        if (root.shown) {
            root.selectedId = -1
            root.members = []
            Library.refreshOutputs()
            root.refreshList()
        }
    }

    Connections {
        target: Daemon
        function onEvent(name, data) {
            if (name === "ryogami.playlist.changed")
                root.refreshList()
        }
        function onReconnected() { root.refreshList() }
    }

    Timer {
        id: nameTimer
        interval: 400
        onTriggered: if (root.selectedId > 0) root.updateField(root.selectedId, "name", nameField.text)
    }
    Timer {
        id: sourceTimer
        interval: 400
        onTriggered: if (root.selectedId > 0) root.updateField(root.selectedId, "source", filterField.text)
    }
    Timer {
        id: dwellTimer
        interval: 400
        onTriggered: if (root.selectedId > 0) root.updateField(root.selectedId, "dwell", root._dwellValue(dwellField.text))
    }

    FolioSheet {
        id: sheet
        visible: !root.cardMode
        reveal: root._reveal
        onDismissed: root.closeRequested()

        FolioMasthead {
            parent: sheet.mastheadArea
            anchors.fill: parent
            breadcrumb: I18n.tr("Playlists  /  %1").arg(root._crumbName)
            onCloseRequested: root.closeRequested()
        }

        FolioIndexShell {
            id: indexShell
            parent: sheet.indexArea
            anchors.fill: parent
            title: I18n.tr("Playlists")
            note: I18n.tr("A manual playlist contains wallpapers you choose. A filtered playlist stays in sync with its rules.")

            Item {
                parent: indexShell.body
                anchors.fill: parent

                Column {
                    id: indexBottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    spacing: 14 * Theme.scale

                    Column {
                        width: parent.width
                        spacing: 9 * Theme.scale

                        FolioRule { width: parent.width; alpha: 0.58 }

                        Item {
                            width: parent.width
                            height: newLabel.implicitHeight

                            Text {
                                id: newLabel
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("New playlist")
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontFine
                                color: Theme.withAlpha(Theme.surfaceText, 0.54)
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root._pad2(root.playlists.length)
                                font.family: Theme.display
                                font.pixelSize: Theme.fontFine
                                color: Theme.withAlpha(Theme.surfaceText, 0.42)
                                renderType: Text.NativeRendering
                            }
                        }

                        RowLayout {
                            width: parent.width
                            spacing: 6 * Theme.scale

                            TextField {
                                id: indexNewField
                                Layout.fillWidth: true
                                variant: "ghost"
                                placeholder: I18n.tr("New playlist name")
                                onCommitted: (t) => { root.createPlaylist(t); indexNewField.text = "" }
                            }
                            FolioAction {
                                label: "\uff0b"
                                fixedWidth: 42 * Theme.scale
                                active: indexNewField.text.trim().length > 0
                                onTriggered: { root.createPlaylist(indexNewField.text); indexNewField.text = "" }
                            }
                        }
                    }

                    Column {
                        id: indexFooter
                        width: parent.width
                        spacing: 7 * Theme.scale

                        FolioRule { width: parent.width; alpha: 0.58 }

                        Text {
                            text: root.anyActive() ? I18n.tr("Active displays") : I18n.tr("Saved playlists")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.54)
                            renderType: Text.NativeRendering
                        }
                        Text {
                            width: parent.width
                            text: root.anyActive()
                                ? (root.assignmentCount() === 1
                                    ? I18n.tr("%1 active assignment").arg(root.assignmentCount())
                                    : I18n.tr("%1 active assignments").arg(root.assignmentCount()))
                                : I18n.tr("%1 saved \u00b7 none active").arg(root.playlists.length)
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontMini
                            color: Theme.withAlpha(Theme.surfaceText, 0.48)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                        FolioDestructiveAction {
                            visible: root.anyActive()
                            glyph: "\u25a0"
                            label: I18n.tr("Stop all")
                            fixedWidth: parent.width
                            confirm: true
                            onTriggered: root.stopPlaylist(0)
                        }
                    }
                }

                Item {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: indexBottom.top
                    anchors.bottomMargin: 14 * Theme.scale
                    clip: true

                    ListView {
                        id: indexList
                        anchors.fill: parent
                        visible: root.playlists.length > 0
                        model: root.playlists
                        spacing: 4 * Theme.scale
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        delegate: PlaylistIndexRow {
                            required property var modelData
                            width: ListView.view.width
                            pid: modelData.id
                            name: (modelData.name && modelData.name.length) ? modelData.name : I18n.tr("(unnamed)")
                            detail: root._indexDetail(modelData)
                            playing: root.isPlaying(modelData.id)
                            selected: root.selectedId === modelData.id
                            onClicked: root.selectPlaylist(modelData.id)
                        }
                    }

                    Column {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: 14 * Theme.scale
                        spacing: 5 * Theme.scale
                        visible: root.playlists.length === 0

                        Text {
                            text: I18n.tr("No playlists yet")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontLabel
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Create one below to begin.")
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontMini
                            color: Theme.withAlpha(Theme.surfaceText, 0.46)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }

        Item {
            parent: sheet.readingArea
            anchors.fill: parent

            PlaylistSequenceRail {
                id: rail
                visible: root.selectedDef !== null
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 380 * Math.max(0.9, Theme.scale)
                members: root.members
                smart: root.smart
                pid: root.selectedId
                onMoveRequested: (key, delta) => root.moveMember(root.selectedId, key, delta)
                onRemoveRequested: (key) => root.removeMember(root.selectedId, key)
            }
            Rectangle {
                id: railDivider
                visible: root.selectedDef !== null
                anchors.right: rail.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.withAlpha(Theme.outline, 0.42)
            }

            Flickable {
                id: editor
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.rightMargin: root.selectedDef ? (rail.width + 1) : 0
                clip: true
                contentWidth: width
                contentHeight: root.selectedDef ? editorCol.implicitHeight : emptyCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: editorCol
                    visible: root.selectedDef !== null
                    width: editor.width
                    topPadding: 30 * Theme.scale
                    bottomPadding: 44 * Theme.scale
                    leftPadding: 34 * Theme.scale
                    rightPadding: 30 * Theme.scale
                    spacing: 28 * Theme.scale

                    readonly property real contentW: width - leftPadding - rightPadding

                    Column {
                        width: editorCol.contentW
                        spacing: 10 * Theme.scale

                        RowLayout {
                            width: parent.width
                            spacing: 10 * Theme.scale

                            Text {
                                text: I18n.tr("Playlists / edit")
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontFine
                                color: Theme.withAlpha(Theme.surfaceText, 0.54)
                                renderType: Text.NativeRendering
                            }
                            Text {
                                text: I18n.tr("ID %1").arg(root.selectedId)
                                font.family: Theme.display
                                font.pixelSize: Theme.fontFine
                                color: Theme.withAlpha(Theme.surfaceText, 0.54)
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: root._stateCopy
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontFine
                                color: root.isPlaying(root.selectedId) ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.46)
                                renderType: Text.NativeRendering
                            }
                        }

                        Text {
                            width: parent.width
                            text: root._displayName
                            font.family: Theme.display
                            font.pixelSize: Theme.fs(42)
                            lineHeight: 0.98
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }

                        RowLayout {
                            width: parent.width
                            spacing: 7 * Theme.scale

                            Text {
                                text: I18n.tr("%1 \u00b7 ready for display assignment")
                                    .arg(root.smart ? I18n.tr("Filtered playlist") : I18n.tr("Manual playlist"))
                                font.family: Theme.sans
                                font.weight: Font.Normal
                                font.pixelSize: Theme.fontXSmall
                                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                renderType: Text.NativeRendering
                            }
                            Item { Layout.fillWidth: true }
                            FolioAction {
                                fixedWidth: 116 * Theme.scale
                                active: true
                                label: root.isPlaying(root.selectedId) ? I18n.tr("Stop playlist") : I18n.tr("Play now")
                                onTriggered: root.isPlaying(root.selectedId) ? root.stopPlaylist(root.selectedId) : root.playNow(root.selectedId)
                            }
                            FolioDestructiveAction {
                                fixedWidth: 68 * Theme.scale
                                label: I18n.tr("Delete")
                                confirm: true
                                onTriggered: root.deletePlaylist(root.selectedId)
                            }
                        }
                    }

                    FolioField {
                        id: filterFieldBlock
                        visible: root.smart
                        width: editorCol.contentW
                        title: I18n.tr("Filtered playlist")
                        desc: I18n.tr("Members resolve from the rules below and stay in sync with your library.")

                        Column {
                            parent: filterFieldBlock.body
                            width: filterFieldBlock.body.width
                            spacing: 14 * Theme.scale

                            RowLayout {
                                width: parent.width
                                spacing: 10 * Theme.scale

                                ChoiceButtons {
                                    value: root._defSource
                                    options: [
                                        { value: "all", label: I18n.tr("All") },
                                        { value: "favourites", label: I18n.tr("Favourites") }
                                    ]
                                    onSelected: (v) => root.updateField(root.selectedId, "source", v)
                                }
                                TextField {
                                    id: filterField
                                    Layout.fillWidth: true
                                    variant: "ghost"
                                    placeholder: I18n.tr("e.g. type:video color:blue tag:cat,-anime")
                                    onEdited: sourceTimer.restart()
                                    onCommitted: (t) => { sourceTimer.stop(); root.updateField(root.selectedId, "source", t) }
                                }
                                FolioAction {
                                    label: I18n.tr("Filter reference")
                                    onTriggered: root._filterHelpOpen = true
                                }
                            }

                            RowLayout {
                                width: parent.width
                                spacing: 13 * Theme.scale

                                Text {
                                    text: I18n.tr("Colours")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fontTiny
                                    color: Theme.withAlpha(Theme.surfaceText, 0.44)
                                    renderType: Text.NativeRendering
                                }
                                PlaylistColourPicker {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: 420 * Theme.scale
                                    source: root._defSource
                                    onPicked: (s) => root.updateField(root.selectedId, "source", s)
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: editorCol.contentW
                        spacing: 20 * Theme.scale

                        FolioField {
                            id: detailsField
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            title: I18n.tr("Playlist details")
                            desc: I18n.tr("Set the name and choose whether wallpapers are added manually or selected by a filter.")

                            Column {
                                parent: detailsField.body
                                width: detailsField.body.width
                                spacing: 11 * Theme.scale

                                TextField {
                                    id: nameField
                                    width: parent.width
                                    variant: "ghost"
                                    placeholder: I18n.tr("Playlist name")
                                    onEdited: nameTimer.restart()
                                    onCommitted: (t) => { nameTimer.stop(); root.updateField(root.selectedId, "name", t) }
                                }
                                ChoiceButtons {
                                    width: parent.width
                                    value: root._defKind
                                    options: [
                                        { value: "curated", label: I18n.tr("Manual") },
                                        { value: "smart", label: I18n.tr("Filtered") }
                                    ]
                                    onSelected: (v) => root.updateField(root.selectedId, "kind", v)
                                }
                                FolioAction {
                                    visible: !root.smart
                                    label: I18n.tr("Add wallpapers")
                                    onTriggered: root._browseOpen = true
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillHeight: true
                            Layout.preferredWidth: 1
                            width: 1
                            color: Theme.withAlpha(Theme.outline, 0.34)
                        }

                        FolioField {
                            id: playbackField
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.alignment: Qt.AlignTop
                            title: I18n.tr("Playback")
                            desc: I18n.tr("Choose the order and how long each wallpaper stays on screen.")

                            Column {
                                parent: playbackField.body
                                width: playbackField.body.width
                                spacing: 11 * Theme.scale

                                ChoiceButtons {
                                    width: parent.width
                                    value: root._defOrder === "sequential" ? "sequential" : "shuffle"
                                    options: [
                                        { value: "shuffle", label: I18n.tr("Shuffle") },
                                        { value: "sequential", label: I18n.tr("Sequential") }
                                    ]
                                    onSelected: (v) => root.updateField(root.selectedId, "order", v)
                                }
                                RowLayout {
                                    width: parent.width
                                    spacing: 6 * Theme.scale

                                    Text {
                                        text: I18n.tr("Every")
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fontBase
                                        color: Theme.withAlpha(Theme.surfaceText, 0.48)
                                        renderType: Text.NativeRendering
                                    }
                                    TextField {
                                        id: dwellField
                                        Layout.preferredWidth: 72 * Theme.scale
                                        variant: "ghost"
                                        placeholder: "600"
                                        onEdited: dwellTimer.restart()
                                        onCommitted: (t) => { dwellTimer.stop(); root.updateField(root.selectedId, "dwell", root._dwellValue(t)) }
                                    }
                                    Text {
                                        text: I18n.tr("seconds (min 5)")
                                        font.family: Theme.sans
                                        font.weight: Font.Normal
                                        font.pixelSize: Theme.fontTiny
                                        color: Theme.withAlpha(Theme.surfaceText, 0.42)
                                        renderType: Text.NativeRendering
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }
                    }

                    FolioField {
                        id: routingField
                        width: editorCol.contentW
                        title: I18n.tr("Apply to displays")
                        desc: I18n.tr("Choose where this playlist runs. Selecting every display creates one shared assignment.")

                        RowLayout {
                            parent: routingField.body
                            width: routingField.body.width
                            spacing: 10 * Theme.scale

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6 * Theme.scale

                                FolioAction {
                                    label: I18n.tr("All")
                                    active: root.allOn(root.selectedId)
                                    onTriggered: root.toggleAll(root.selectedId)
                                }
                                Repeater {
                                    model: root._outputNames
                                    delegate: FolioAction {
                                        required property string modelData
                                        label: modelData
                                        active: root.allOn(root.selectedId) || root.assignedId(modelData) === root.selectedId
                                        onTriggered: root.toggleOutput(modelData, root.selectedId)
                                    }
                                }
                            }
                            Text {
                                text: root._routingState
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontFine
                                color: root.isPlaying(root.selectedId) ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.44)
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }

                Column {
                    id: emptyCol
                    visible: root.selectedDef === null
                    width: editor.width
                    topPadding: 23 * Theme.scale
                    bottomPadding: 24 * Theme.scale
                    leftPadding: 27 * Theme.scale
                    rightPadding: 27 * Theme.scale
                    spacing: 10 * Theme.scale

                    readonly property real contentW: width - leftPadding - rightPadding

                    Text {
                        text: I18n.tr("Playlists / library")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.54)
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: emptyCol.contentW
                        text: I18n.tr("Build a rotation")
                        font.family: Theme.display
                        font.pixelSize: Theme.fs(34)
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                    }
                    FolioRule { width: emptyCol.contentW; alpha: 0.58 }
                    Column {
                        width: emptyCol.contentW
                        spacing: 7 * Theme.scale
                        Text {
                            text: I18n.tr("Choose a playlist from the index")
                            font.family: Theme.display
                            font.pixelSize: Theme.fs(19)
                            color: Theme.surfaceText
                            renderType: Text.NativeRendering
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Pick one on the left to edit its wallpapers, order, and displays.")
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontXSmall
                            color: Theme.withAlpha(Theme.surfaceText, 0.5)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }

    PlaylistBrowsePopover {
        anchors.fill: parent
        visible: root._browseOpen
        state: root.state
        pid: root.selectedId
        playlistName: root._crumbName
        onCloseRequested: root._browseOpen = false
    }
    PlaylistFilterHelp {
        anchors.fill: parent
        visible: root._filterHelpOpen
        onCloseRequested: root._filterHelpOpen = false
    }

    PlaylistCardPicker {
        anchors.fill: parent
        visible: root.cardMode
        state: root.state
        wallKey: root.cardKey
        wallName: root.cardName
        onCloseRequested: root.closeRequested()
    }

    Keys.onEscapePressed: {
        if (root._browseOpen)
            root._browseOpen = false
        else if (root._filterHelpOpen)
            root._filterHelpOpen = false
        else
            root.closeRequested()
    }
}
