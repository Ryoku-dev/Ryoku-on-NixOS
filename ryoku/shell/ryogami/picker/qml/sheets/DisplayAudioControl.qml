import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

// Release-committed: volumeMoved streams while dragging, volumeReleased commits.
RowLayout {
    id: root

    property bool muted: false
    property int volume: 100
    property bool playing: true

    signal muteToggled(bool wantMuted)
    signal volumeMoved(int v)
    signal volumeReleased(int v)

    spacing: 7 * Theme.scale

    FolioAction {
        Layout.preferredWidth: 74 * Theme.scale
        fixedWidth: 74 * Theme.scale
        label: root.muted ? I18n.tr("Muted") : I18n.tr("Sound")
        active: !root.muted
        onTriggered: root.muteToggled(!root.muted)
    }

    FolioSlider {
        id: vol
        Layout.fillWidth: true
        from: 0
        to: 100
        step: 1
        value: root.volume
        onMoved: (v) => root.volumeMoved(Math.round(v))
        onReleased: (v) => root.volumeReleased(Math.round(v))
    }

    // An external volume change reaches the slider unless the user is mid-drag.
    Connections {
        target: root
        function onVolumeChanged() { if (!vol.dragging) vol.value = root.volume }
    }

    Text {
        Layout.preferredWidth: 42 * Theme.scale
        text: Math.round(vol.value) + "%"
        font.family: Theme.display
        font.pixelSize: Theme.fontSmall
        color: (root.muted || !root.playing) ? Theme.withAlpha(Theme.surfaceText, 0.42) : Theme.surfaceText
        horizontalAlignment: Text.AlignRight
        renderType: Text.NativeRendering
    }
}
