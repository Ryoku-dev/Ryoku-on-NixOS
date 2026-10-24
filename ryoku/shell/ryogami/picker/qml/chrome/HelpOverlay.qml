import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state

    anchors.fill: parent

    readonly property bool shown: root.state ? root.state.helpOpen : false

    property real reveal: 0
    states: State { name: "open"; when: root.shown; PropertyChanges { target: root; reveal: 1 } }
    Behavior on reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: reveal > 0.01

    property int settingsRev: 0
    Connections {
        target: Settings
        function onChanged(key, value) { root.settingsRev++ }
    }
    function binding(name, def) {
        root.settingsRev
        var v = Settings.value("keys." + name)
        return (v === undefined || v === null || v === "") ? def : v
    }

    readonly property var bindings: [
        { name: "select", title: I18n.tr("Select, then apply"), def: "click" },
        { name: "apply", title: I18n.tr("Apply wallpaper"), def: "enter" },
        { name: "flip", title: I18n.tr("Flip card for details"), def: "right-click" },
        { name: "reveal", title: I18n.tr("Flip the hand to preview"), def: "v" },
        { name: "favourite", title: I18n.tr("Favourite card"), def: "f" },
        { name: "effects", title: I18n.tr("Choose displays"), def: "ctrl+click" },
        { name: "studio", title: I18n.tr("Effects studio"), def: "shift+right-click" },
        { name: "sceneProperties", title: I18n.tr("Scene properties"), def: "shift+w" },
        { name: "playlists", title: I18n.tr("Toggle playlists"), def: "p" },
        { name: "settings", title: I18n.tr("Settings panel"), def: "shift+s" },
        { name: "help", title: I18n.tr("Shortcut sheet"), def: "?" },
        { name: "themePanel", title: I18n.tr("Colour panel"), def: "c" },
        { name: "tagCloud", title: I18n.tr("Toggle search"), def: "shift+down" },
        { name: "tagMode", title: I18n.tr("Multi-tag select mode"), def: "t" },
        { name: "filterBar", title: I18n.tr("Show/hide filter bar"), def: "shift+up" },
        { name: "folderPrev", title: I18n.tr("Previous folder"), def: "ctrl+left" },
        { name: "folderNext", title: I18n.tr("Next folder"), def: "ctrl+right" },
        { name: "folderToggle", title: I18n.tr("Toggle All/Main"), def: "ctrl+m" },
        { name: "hiddenFolders", title: I18n.tr("Show/hide hidden folders"), def: "ctrl+h" },
        { name: "colorPrev", title: I18n.tr("Cycle colour filter left"), def: "shift+left" },
        { name: "colorNext", title: I18n.tr("Cycle colour filter right"), def: "shift+right" },
        { name: "navLeft", title: I18n.tr("Navigate left"), def: "left" },
        { name: "navRight", title: I18n.tr("Navigate right"), def: "right" },
        { name: "navUp", title: I18n.tr("Navigate up"), def: "up" },
        { name: "navDown", title: I18n.tr("Navigate down"), def: "down" },
        { name: "autocomplete", title: I18n.tr("Complete tag"), def: "tab" },
        { name: "typePrev", title: I18n.tr("Previous wallpaper type"), def: "shift+tab" },
        { name: "typeNext", title: I18n.tr("Next wallpaper type"), def: "tab" },
        { name: "sortPrev", title: I18n.tr("Previous sort"), def: "alt+left" },
        { name: "sortNext", title: I18n.tr("Next sort"), def: "alt+right" },
        { name: "randomRotate", title: I18n.tr("Toggle random rotation"), def: "ctrl+r" },
        { name: "searchMode", title: I18n.tr("Switch between Tags and Describe"), def: "ctrl+tab" },
        { name: "downloads", title: I18n.tr("Toggle downloads"), def: "ctrl+d" },
        { name: "sourceWallhaven", title: I18n.tr("Switch to Wallhaven"), def: "1" },
        { name: "sourceSteam", title: I18n.tr("Switch to Steam Workshop"), def: "2" },
        { name: "sourceUnsplash", title: I18n.tr("Switch to Unsplash"), def: "3" },
        { name: "sourcePexels", title: I18n.tr("Switch to Pexels"), def: "4" },
        { name: "sourceYoutube", title: I18n.tr("Switch to YouTube"), def: "5" },
        { name: "sourceBing", title: I18n.tr("Switch to Bing Daily"), def: "6" }
    ]

    function _rows(mouse) {
        root.settingsRev
        var out = []
        for (var i = 0; i < root.bindings.length; ++i) {
            var b = root.bindings[i]
            var chord = root.binding(b.name, b.def)
            var isMouse = String(chord).indexOf("click") >= 0
            if (isMouse === mouse)
                out.push({ key: chord, desc: String(b.title).toLowerCase() })
        }
        if (mouse) {
            out.push({ key: I18n.tr("Wheel"), desc: I18n.tr("browse / scroll") })
            out.push({ key: I18n.tr("Hover"), desc: I18n.tr("preview videos") })
        } else {
            out.push({ key: "Esc", desc: I18n.tr("close / back / quit") })
        }
        return out
    }

    Scrim {
        anchors.fill: parent
        alpha: 0.5
        reveal: root.reveal
        onDismissed: if (root.state) root.state.helpOpen = false
    }

    ChamferPanel {
        id: panel
        anchors.centerIn: parent
        reveal: root.reveal
        opacity: root.reveal
        width: 560 * Theme.scale
        height: content.implicitHeight + 32 * Theme.scale
        transform: Translate { y: (1 - root.reveal) * 10 * Theme.scale }

        Column {
            id: content
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 16 * Theme.scale
            anchors.leftMargin: 20 * Theme.scale
            anchors.rightMargin: 20 * Theme.scale
            spacing: 14 * Theme.scale

            Item {
                width: parent.width
                height: 22 * Theme.scale
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Shortcuts")
                    font.family: Theme.display
                    font.pixelSize: Theme.fontLead
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u00d7"
                    font.family: Theme.sans; font.weight: Font.Medium
                    font.pixelSize: Theme.fontHead
                    color: closeMouse.containsMouse ? Theme.surfaceText : Theme.withAlpha(Theme.surfaceText, 0.7)
                    renderType: Text.NativeRendering
                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        anchors.margins: -8 * Theme.scale
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.state) root.state.helpOpen = false
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 30 * Theme.scale

                Column {
                    width: (parent.width - 30 * Theme.scale) / 2
                    spacing: 7 * Theme.scale
                    Text {
                        text: I18n.tr("Keyboard")
                        font.family: Theme.sans; font.weight: Font.DemiBold
                        font.pixelSize: Theme.fontLabel
                        color: Theme.withAlpha(Theme.surfaceText, 0.78)
                        renderType: Text.NativeRendering
                    }
                    Repeater {
                        model: root._rows(false)
                        delegate: HelpRow { required property var modelData; keyLabel: modelData.key; desc: modelData.desc }
                    }
                }

                Column {
                    width: (parent.width - 30 * Theme.scale) / 2
                    spacing: 7 * Theme.scale
                    Text {
                        text: I18n.tr("Mouse")
                        font.family: Theme.sans; font.weight: Font.DemiBold
                        font.pixelSize: Theme.fontLabel
                        color: Theme.withAlpha(Theme.surfaceText, 0.78)
                        renderType: Text.NativeRendering
                    }
                    Repeater {
                        model: root._rows(true)
                        delegate: HelpRow { required property var modelData; keyLabel: modelData.key; desc: modelData.desc }
                    }
                }
            }
        }
    }

    component HelpRow: Row {
        id: helpRow
        property string keyLabel: ""
        property string desc: ""
        width: parent ? parent.width : 0
        spacing: 10 * Theme.scale
        Rectangle {
            width: 92 * Theme.scale
            height: chord.implicitHeight + 6 * Theme.scale
            anchors.verticalCenter: parent.verticalCenter
            radius: Theme.radius
            color: Theme.withAlpha(Theme.surfaceText, 0.05)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.4)
            Text {
                id: chord
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8 * Theme.scale
                anchors.rightMargin: 8 * Theme.scale
                anchors.verticalCenter: parent.verticalCenter
                text: helpRow.keyLabel
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontBody
                color: Theme.surfaceText
                elide: Text.ElideRight
                renderType: Text.NativeRendering
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: helpRow.width - 92 * Theme.scale - 10 * Theme.scale
            text: helpRow.desc
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontBody
            color: Theme.withAlpha(Theme.surfaceText, 0.85)
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
    }
}
