import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state
    property var args
    property bool shown: false
    signal closeRequested()

    anchors.fill: parent
    focus: true

    property real _reveal: shown ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: _reveal > 0.001

    property var _outputs: []
    function _refresh() {
        var out = []
        var src = Library.outputs || []
        for (var i = 0; i < src.length; i++)
            out.push(src[i])
        root._outputs = out
    }

    Component.onCompleted: { Library.refreshOutputs(); root._refresh() }
    onShownChanged: if (root.shown) { Library.refreshOutputs(); root._refresh() }

    Connections {
        target: Library
        function onOutputsChanged() { root._refresh() }
    }

    property var _paused: ({})
    function _isPaused(name) { return root._paused[name] === true }
    function _setPaused(name, p) {
        var m = ({})
        for (var k in root._paused)
            m[k] = root._paused[k]
        m[name] = p
        root._paused = m
    }

    function _clampVol(v) {
        var n = Number(v)
        if (v === undefined || v === null || isNaN(n)) n = 100
        return Math.max(0, Math.min(100, Math.round(n)))
    }
    function _hasAudio(o) {
        var c = o && o.current ? o.current : null
        var t = c ? (c.type || "") : ""
        return t === "video" || t === "we"
    }

    // Outputs showing the same source share one aligned mute and volume (the first unmuted member's, else the max).
    function _rowsFor(outs) {
        var list = outs || []
        var groups = ({})
        var byName = ({})
        for (var i = 0; i < list.length; i++) {
            var o = list[i]
            byName[o.name] = o
            var c = o.current || ({})
            var t = c.type || ""
            var k = c.key || ""
            if ((t === "video" || t === "we") && k) {
                var gk = t + "\u0000" + k
                if (!groups[gk]) groups[gk] = []
                groups[gk].push(o.name)
            }
        }
        var info = ({})
        for (var g in groups) {
            var names = groups[g]
            var allMuted = true, firstUnmuted = -1, maxVol = 0
            for (var j = 0; j < names.length; j++) {
                var m = byName[names[j]].current || ({})
                var vol = root._clampVol(m.volume)
                if (vol > maxVol) maxVol = vol
                if (!(m.mute === true)) { allMuted = false; if (firstUnmuted < 0) firstUnmuted = vol }
            }
            info[g] = { mute: allMuted, volume: firstUnmuted >= 0 ? firstUnmuted : maxVol }
        }
        var rows = []
        for (var r = 0; r < list.length; r++) {
            var oo = list[r]
            var cc = oo.current || ({})
            var tt = cc.type || ""
            var kk = cc.key || ""
            var gkk = ((tt === "video" || tt === "we") && kk) ? (tt + "\u0000" + kk) : ""
            var gnames = gkk ? groups[gkk] : [oo.name]
            var mute = gkk ? info[gkk].mute : (cc.mute === true)
            var volume = gkk ? info[gkk].volume : root._clampVol(cc.volume)
            rows.push({ output: oo, ordinal: r + 1, groupNames: gnames,
                        shared: gnames.length > 1, muted: mute, volume: volume })
        }
        return rows
    }

    readonly property var _rowModels: root._rowsFor(root._outputs)
    readonly property int _total: root._rowModels.length
    readonly property int _available: {
        var n = 0
        var rows = root._rowModels
        for (var i = 0; i < rows.length; i++)
            if (root._hasAudio(rows[i].output)) n++
        return n
    }
    readonly property int _sounding: {
        var n = 0
        var rows = root._rowModels
        for (var i = 0; i < rows.length; i++) {
            var rm = rows[i]
            if (root._hasAudio(rm.output) && !rm.muted && !root._isPaused(rm.output.name)) n++
        }
        return n
    }

    SettingValue { id: svMute; key: "wallpaperMute" }
    SettingValue { id: svVolume; key: "wallpaperVolume" }
    SettingValue { id: svDuck; key: "playback.muteOnOtherAudio" }

    readonly property bool _globalMuted: svMute.value === true
    readonly property int _globalVolume: root._clampVol(svVolume.value)
    readonly property bool _ducking: svDuck.value === true

    function _setAudio(params) {
        Daemon.call("wall.set_audio", params, function(res, err) {
            if (err)
                root.state.toast(err.message || I18n.tr("Could not change wallpaper audio."), "error")
        })
    }
    function _setPausedRpc(name, paused) {
        root._setPaused(name, paused)
        Daemon.call("wall.pause", { outputs: [name], paused: paused }, function(res, err) {
            if (err) {
                root._setPaused(name, !paused)
                root.state.toast(err.message || I18n.tr("Could not change wallpaper playback."), "error")
            }
        })
    }

    FolioSheet {
        id: sheet
        reveal: root._reveal
        onDismissed: root.closeRequested()

        FolioMasthead {
            parent: sheet.mastheadArea
            anchors.fill: parent
            breadcrumb: I18n.tr("Audio / mixer")
            onCloseRequested: root.closeRequested()
        }

        FolioIndexShell {
            id: indexShell
            parent: sheet.indexArea
            anchors.fill: parent
            title: I18n.tr("Audio")
            note: I18n.tr("Pause wallpapers by display. Displays showing the same source share volume and mute settings.")

            Item {
                parent: indexShell.body
                anchors.fill: parent

                Column {
                    id: chipsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 9 * Theme.scale

                    Text {
                        visible: root._rowModels.length === 0
                        width: parent.width
                        text: I18n.tr("Detecting outputs")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontSmall
                        color: Theme.withAlpha(Theme.surfaceText, 0.5)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }

                    Repeater {
                        model: root._rowModels
                        delegate: AudioChannelChip {
                            required property var modelData
                            width: chipsCol.width
                            output: modelData.output
                            ordinal: modelData.ordinal
                            shared: modelData.shared
                            muted: modelData.muted
                            manual: root._isPaused(modelData.output.name)
                        }
                    }
                }

                Column {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 7 * Theme.scale

                    FolioRule { width: parent.width; alpha: 0.5 }

                    Text {
                        text: I18n.tr("Current audio")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.54)
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("%1 playing \u00b7 %2 with audio").arg(root._sounding).arg(root._available)
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontMini
                        color: Theme.withAlpha(Theme.surfaceText, 0.48)
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        ColumnLayout {
            parent: sheet.readingArea
            anchors.fill: parent
            anchors.topMargin: 23 * Theme.scale
            anchors.leftMargin: 27 * Theme.scale
            anchors.rightMargin: 27 * Theme.scale
            anchors.bottomMargin: 23 * Theme.scale
            spacing: 12 * Theme.scale

            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(headLeft.implicitHeight, headRight.implicitHeight)

                Column {
                    id: headLeft
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.right: headRight.left
                    anchors.rightMargin: 20 * Theme.scale
                    spacing: 3 * Theme.scale

                    Text {
                        text: I18n.tr("Audio / displays")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.54)
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("Wallpaper mixer")
                        font.family: Theme.display
                        font.pixelSize: Theme.fs(34)
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                }

                Column {
                    id: headRight
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: Math.min(340 * Theme.scale, parent.width * 0.44)
                    spacing: 4 * Theme.scale

                    Text {
                        width: parent.width
                        text: I18n.tr("Pause each display independently. Volume and mute stay linked for shared wallpapers.")
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontSmall
                        color: Theme.withAlpha(Theme.surfaceText, 0.56)
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("%1 output(s) \u00b7 %2 with audio \u00b7 %3 playing").arg(root._total).arg(root._available).arg(root._sounding)
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.42)
                        horizontalAlignment: Text.AlignRight
                        wrapMode: Text.WordWrap
                        renderType: Text.NativeRendering
                    }
                }
            }

            FolioField {
                id: globalField
                Layout.fillWidth: true
                title: I18n.tr("Global")
                desc: I18n.tr("These defaults apply to every display unless a channel below overrides it.")

                Column {
                    parent: globalField.body
                    width: globalField.body.width
                    spacing: 9 * Theme.scale

                    RowLayout {
                        width: parent.width
                        spacing: 9 * Theme.scale

                        Text {
                            Layout.preferredWidth: 90 * Theme.scale
                            Layout.alignment: Qt.AlignVCenter
                            text: I18n.tr("Default audio")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.46)
                            renderType: Text.NativeRendering
                        }
                        DisplayAudioControl {
                            Layout.fillWidth: true
                            muted: root._globalMuted
                            volume: root._globalVolume
                            playing: !root._globalMuted
                            onMuteToggled: (m) => Settings.set("wallpaperMute", m)
                            onVolumeReleased: (v) => Settings.set("wallpaperVolume", v)
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 9 * Theme.scale

                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: I18n.tr("Pause wallpaper audio while other apps play sound")
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontBody
                            color: Theme.withAlpha(Theme.surfaceText, 0.72)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                        FolioAction {
                            Layout.alignment: Qt.AlignVCenter
                            fixedWidth: 64 * Theme.scale
                            label: root._ducking ? I18n.tr("On") : I18n.tr("Off")
                            active: root._ducking
                            onTriggered: Settings.set("playback.muteOnOtherAudio", !root._ducking)
                        }
                    }
                }
            }

            FolioField {
                Layout.fillWidth: true
                title: I18n.tr("Output channels")
                desc: I18n.tr("Muted channels stay dark. Displays showing the same source share volume and mute settings.")
            }

            Flickable {
                id: listFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: listCol.height
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: listCol
                    width: listFlick.width
                    spacing: 9 * Theme.scale

                    Rectangle {
                        visible: root._rowModels.length === 0
                        width: parent.width
                        color: Theme.withAlpha(Theme.surfaceContainer, 0.54)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outline, 0.52)
                        implicitHeight: emptyCol.implicitHeight + 36 * Theme.scale

                        Column {
                            id: emptyCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 18 * Theme.scale
                            spacing: 4 * Theme.scale

                            Text {
                                width: parent.width
                                text: I18n.tr("Looking for displays")
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontField
                                color: Theme.surfaceText
                                renderType: Text.NativeRendering
                            }
                            Text {
                                width: parent.width
                                text: I18n.tr("Audio controls will appear when the wallpaper service reports its displays.")
                                font.family: Theme.sans
                                font.weight: Font.Normal
                                font.pixelSize: Theme.fontSmall
                                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }
                        }
                    }

                    Repeater {
                        model: root._rowModels
                        delegate: AudioChannelRow {
                            required property var modelData
                            width: listCol.width
                            output: modelData.output
                            groupNames: modelData.groupNames
                            shared: modelData.shared
                            ordinal: modelData.ordinal
                            groupMuted: modelData.muted
                            groupVolume: modelData.volume
                            manual: root._isPaused(modelData.output.name)

                            onMuteToggled: (m) => root._setAudio({ mute: m, outputs: modelData.groupNames })
                            onVolumeReleased: (v) => root._setAudio({ volume: v, mute: (v === 0), outputs: modelData.groupNames })
                            onPauseToggled: (wantManual) => root._setPausedRpc(modelData.output.name, wantManual)
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: footerCol.implicitHeight

                Column {
                    id: footerCol
                    width: parent.width
                    spacing: 9 * Theme.scale

                    FolioRule { width: parent.width; alpha: 0.5 }

                    RowLayout {
                        width: parent.width
                        spacing: 8 * Theme.scale

                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2 * Theme.scale

                            Row {
                                spacing: 8 * Theme.scale
                                Text {
                                    text: I18n.tr("Current state")
                                    font.family: Theme.sans
                                    font.weight: Font.DemiBold
                                    font.pixelSize: Theme.fontLabel
                                    color: Theme.surfaceText
                                    renderType: Text.NativeRendering
                                }
                            }
                            Text {
                                width: parent.width
                                text: root._sounding === 0 ? I18n.tr("No wallpaper audio is currently playing.")
                                    : I18n.tr("Highlighted channels are playing audio.")
                                font.family: Theme.sans
                                font.weight: Font.Normal
                                font.pixelSize: Theme.fontMini
                                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                wrapMode: Text.WordWrap
                                renderType: Text.NativeRendering
                            }
                        }

                        FolioAction {
                            Layout.alignment: Qt.AlignVCenter
                            fixedWidth: 150 * Theme.scale
                            label: I18n.tr("Close mixer")
                            onTriggered: root.closeRequested()
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root.closeRequested()
}
