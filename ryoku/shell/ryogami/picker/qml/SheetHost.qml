import QtQuick

// Each sheet is built the first time it opens and stays resident, so reopening never rebuilds.
// Collapsed folio categories build their rows lazily, so the first open lays out only what it shows.
Item {
    id: host

    required property PickerState state

    component SheetSlot: Loader {
        id: slot
        required property string sheetName
        anchors.fill: parent
        property bool _everOpened: false
        readonly property bool wanted: host.state.sheet === slot.sheetName
        onWantedChanged: if (slot.wanted) slot._everOpened = true
        active: slot._everOpened
        // Bound after loading, so the first open changes shown like every later one.
        onLoaded: slot.item.shown = Qt.binding(() => slot.wanted)
    }

    SheetSlot { sheetName: "settings"; sourceComponent: cSettings }
    SheetSlot { sheetName: "browser"; sourceComponent: cBrowser }
    SheetSlot { sheetName: "playlists"; sourceComponent: cPlaylists }
    SheetSlot { sheetName: "schedule"; sourceComponent: cSchedule }
    SheetSlot { sheetName: "effects"; sourceComponent: cEffects }
    SheetSlot { sheetName: "audio"; sourceComponent: cAudio }
    SheetSlot { sheetName: "sceneProperties"; sourceComponent: cSceneProps }
    SheetSlot { sheetName: "themeDesigner"; sourceComponent: cThemeDesigner }
    SheetSlot { sheetName: "themeAudition"; sourceComponent: cThemeAudition }

    Component {
        id: cSettings
        SettingsFolio {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cPlaylists
        PlaylistsSheet {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cSchedule
        ScheduleSheet {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cEffects
        EffectsStudio {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cAudio
        AudioPanel {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cSceneProps
        ScenePropertiesPanel {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cThemeDesigner
        ThemeDesignerSheet {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cThemeAudition
        ThemeAudition {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
    Component {
        id: cBrowser
        BrowserPanel {
            anchors.fill: parent
            state: host.state
            args: host.state.sheetArgs
            onCloseRequested: host.state.closeSheet()
        }
    }
}
