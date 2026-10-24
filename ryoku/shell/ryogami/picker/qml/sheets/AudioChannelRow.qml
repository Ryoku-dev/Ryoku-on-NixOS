import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Rectangle {
    id: row

    property var output: null
    property var groupNames: []
    property bool shared: false
    property int ordinal: 1
    // Shared members display and move together.
    property bool groupMuted: false
    property int groupVolume: 100
    property bool manual: false

    signal muteToggled(bool wantMuted)
    signal volumeMoved(int v)
    signal volumeReleased(int v)
    signal pauseToggled(bool wantManual)

    readonly property var _cur: (row.output && row.output.current) ? row.output.current : null
    readonly property string _type: row._cur ? (row._cur.type || "") : ""
    readonly property bool hasAudio: row._type === "video" || row._type === "we"
    readonly property string _path: row._cur ? (row._cur.path || "") : ""
    readonly property bool _playing: row.hasAudio && !row.groupMuted && !row.manual

    // Optimistic until the daemon reports the committed volume back.
    property int _vol: row.groupVolume
    onGroupVolumeChanged: row._vol = row.groupVolume

    readonly property string _outName: row.output ? (row.output.name || "") : ""
    readonly property string _sourceLabel: {
        if (row._type === "video") {
            if (row._path) { var s = row._path.split("/"); return s[s.length - 1] }
            return I18n.tr("Video")
        }
        if (row._type === "we")
            return I18n.tr("Wallpaper Engine")
        if (row._type === "static")
            return I18n.tr("Static image")
        return "\u2013"
    }
    readonly property string _kind: {
        if (row._type === "video") return I18n.tr("Video wallpaper")
        if (row._type === "we") return I18n.tr("Wallpaper Engine scene")
        if (row._type === "static") return I18n.tr("Static wallpaper")
        return I18n.tr("No wallpaper source")
    }
    readonly property string _stateText: !row.hasAudio ? I18n.tr("\u2013  No audio")
        : row.manual ? I18n.tr("Paused")
        : row.groupMuted ? I18n.tr("\u25cb  Muted")
        : I18n.tr("\u25cf  Sound")

    color: Theme.withAlpha(Theme.surfaceContainer, 0.48)
    border.width: 1
    border.color: row._playing ? Theme.withAlpha(Theme.surfaceText, 0.55) : Theme.withAlpha(Theme.outline, 0.5)
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    implicitHeight: col.implicitHeight + col.anchors.topMargin + 9 * Theme.scale

    Column {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 10 * Theme.scale
        anchors.rightMargin: 10 * Theme.scale
        anchors.topMargin: 3 * Theme.scale
        spacing: 7 * Theme.scale

        Rectangle {
            width: parent.width
            color: Theme.withAlpha(Theme.surfaceContainer, 0.58)
            border.width: 1
            border.color: row._playing ? Theme.withAlpha(Theme.surfaceText, 0.55) : Theme.withAlpha(Theme.outline, 0.52)
            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
            implicitHeight: summary.implicitHeight + 18 * Theme.scale

            Item {
                id: summary
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 10 * Theme.scale
                anchors.rightMargin: 10 * Theme.scale
                anchors.topMargin: 9 * Theme.scale
                implicitHeight: Math.max(details.implicitHeight, stateCol.implicitHeight)

                Text {
                    id: ordText
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: row.ordinal < 10 ? ("0" + row.ordinal) : String(row.ordinal)
                    font.family: Theme.display
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, row._playing ? 0.85 : 0.5)
                    renderType: Text.NativeRendering
                }

                Column {
                    id: details
                    anchors.left: ordText.right
                    anchors.right: stateCol.left
                    anchors.top: parent.top
                    anchors.leftMargin: 9 * Theme.scale
                    anchors.rightMargin: 9 * Theme.scale
                    spacing: 2 * Theme.scale

                    Text {
                        width: parent.width
                        text: (row._outName === "" || row._outName === "*") ? I18n.tr("Shared outputs") : row._outName
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontLead
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: row._sourceLabel
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontSmall
                        color: Theme.withAlpha(Theme.surfaceText, 0.52)
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                    Text {
                        width: parent.width
                        text: row._kind
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.4)
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }
                }

                Column {
                    id: stateCol
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 2 * Theme.scale

                    Text {
                        anchors.right: parent.right
                        text: row._stateText
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontSmall
                        color: row._playing ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.56)
                        renderType: Text.NativeRendering
                    }
                    Text {
                        anchors.right: parent.right
                        visible: row.hasAudio
                        text: row.shared ? I18n.tr("Linked source") : I18n.tr("Independent source")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontTiny
                        color: Theme.withAlpha(Theme.surfaceText, 0.38)
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        RowLayout {
            width: parent.width
            visible: row.hasAudio
            spacing: 9 * Theme.scale

            Text {
                Layout.preferredWidth: 72 * Theme.scale
                Layout.alignment: Qt.AlignVCenter
                text: I18n.tr("Audio")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.46)
                renderType: Text.NativeRendering
            }

            DisplayAudioControl {
                Layout.fillWidth: true
                muted: row.groupMuted
                volume: row._vol
                playing: row._playing
                onMuteToggled: (m) => row.muteToggled(m)
                onVolumeMoved: (v) => { row._vol = v; row.volumeMoved(v) }
                onVolumeReleased: (v) => { row._vol = v; row.volumeReleased(v) }
            }
        }

        RowLayout {
            width: parent.width
            visible: !row.hasAudio
            spacing: 9 * Theme.scale

            Text {
                Layout.preferredWidth: 72 * Theme.scale
                Layout.alignment: Qt.AlignTop
                text: I18n.tr("Audio")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.46)
                renderType: Text.NativeRendering
            }
            Text {
                Layout.fillWidth: true
                text: I18n.tr("This wallpaper does not expose an audio channel.")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBase
                color: Theme.withAlpha(Theme.surfaceText, 0.46)
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
        }

        RowLayout {
            width: parent.width
            visible: row.hasAudio
            spacing: 9 * Theme.scale

            Text {
                Layout.preferredWidth: 72 * Theme.scale
                Layout.alignment: Qt.AlignVCenter
                text: I18n.tr("Wallpaper")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.46)
                renderType: Text.NativeRendering
            }
            DisplayPlaybackControl {
                Layout.alignment: Qt.AlignVCenter
                manual: row.manual
                paused: false
                onPauseToggled: (wantManual) => row.pauseToggled(wantManual)
            }
            Item { Layout.fillWidth: true }
        }
    }
}
