pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ryoku.Ui.Singletons

// Ryoku keybind cheatsheet -- a one-shot `qs -c keys` app bound to Super+K. It
// maps a full-screen layer-shell overlay on every monitor (only the focused one
// carries the card and keyboard), dim + blurred behind by the `ryoku-keys` layer
// rule in decoration.lua. The legend comes from `ryoku-hub keybinds`, the same
// catalog the Hub parses from binds.lua, so there is one source and no drift.
// Read-only. Quit on close so the launch flock releases and it holds no memory
// while idle.
ShellRoot {
    id: app

    property var categories: []
    property bool loaded: false
    property bool closing: false

    Process {
        running: true
        command: ["ryoku-hub", "keybinds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text);
                    // A bind the user switched off holds no chord, so the sheet
                    // leaves it out: this list answers "what can I press", and a
                    // row with no keys answers nothing. The Hub still lists it,
                    // which is where it gets a chord back.
                    var cats = (o && o.categories) ? o.categories : [];
                    app.categories = cats.map(function (c) {
                        return {
                            name: c.name,
                            binds: (c.binds || []).filter(function (b) { return !b.disabled; })
                        };
                    }).filter(function (c) { return c.binds.length > 0; });
                } catch (e) {
                    app.categories = [];
                }
                app.loaded = true;
            }
        }
    }

    function dismiss() {
        if (app.closing)
            return;
        app.closing = true;
        quitTimer.start();
    }
    Timer {
        id: quitTimer
        interval: Tokens.durSmall + 30
        onTriggered: Qt.quit()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "ryoku-keys"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors { top: true; bottom: true; left: true; right: true }

            // root.screen is briefly null while an output tears down; guard the
            // read so keyboard focus never latches on a stale value.
            readonly property bool onFocused: {
                var fo = Wm.focusedOutput;
                return fo ? (modelData ? fo === modelData.name : false) : true;
            }
            WlrLayershell.keyboardFocus: (win.onFocused && !app.closing)
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            property real appear: 0
            NumberAnimation on appear {
                running: true
                from: 0
                to: 1
                duration: Tokens.durNormal
                easing.type: Easing.OutCubic
            }

            FocusScope {
                anchors.fill: parent
                focus: true
                opacity: app.closing ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic } }
                Keys.onEscapePressed: app.dismiss()

                // Dim the desktop so the frosted card reads on any wallpaper.
                Rectangle {
                    anchors.fill: parent
                    color: Tokens.paper
                    opacity: 0.42 * win.appear
                }
                // Click-out closes.
                MouseArea {
                    anchors.fill: parent
                    onClicked: app.dismiss()
                }

                Cheatsheet {
                    anchors.fill: parent
                    visible: win.onFocused
                    categories: app.categories
                    loaded: app.loaded
                    appear: win.appear
                    onRequestClose: app.dismiss()
                }
            }
        }
    }
}
