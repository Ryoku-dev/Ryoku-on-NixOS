pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import shell.services
import "ii" as Ii

/**
 * The ii dock design's global host.
 *
 * The port's Dock.qml is a Scope: it repeats itself across the screens it is
 * told to cover, so this host mounts it once for the whole session, gated on
 * the shared store selecting the "ii" design. The same gate owns the rest of
 * the design's bundle: the live-draw overlay per screen, the alarm ringing
 * popup, the clock app window and the dock's own settings page.
 */
Scope {
    id: root

    // Both open paths (the dock's own gear and the Stage Editor's row) close
    // through here: the bridge flag plus the shared design-settings flag.
    function closeSettings(): void {
        Ii.GlobalStates.settingsOpen = false;
        Dock.designSettingsOpen = false;
    }

    // The Stage Editor's dock page (and any external caller) opens the design's
    // own settings surface through this channel.
    IpcHandler {
        target: "ii-dock"
        function openSettings(): void {
            Dock.designSettingsOpen = true;
        }
        function closeSettings(): void {
            root.closeSettings();
        }
    }

    readonly property bool active: Dock.design === "ii" && Dock.cfg("enabled", false)

    Loader {
        active: root.active
        asynchronous: true
        sourceComponent: Component {
            Ii.Dock {}
        }
    }

    // Live draw: one window per screen, mounted while the feature is on.
    Repeater {
        model: root.active ? Quickshell.screens : []

        delegate: Loader {
            required property var modelData
            active: Ii.LiveDraw.enabled
            sourceComponent: Component {
                Ii.LiveDrawWindow {
                }
            }
            onLoaded: if (item)
                item.screen = modelData
        }
    }

    Loader {
        active: root.active
        sourceComponent: Component {
            Ii.AlarmRingingPopup {}
        }
    }

    Loader {
        active: root.active
        asynchronous: true
        sourceComponent: Component {
            Ii.ClockAppWindow {}
        }
    }

    // The dock's settings: the port's own page, mounted full-screen while the
    // bridge asks for it (the dock's tiles and edit menus open it through
    // GlobalStates.openSettingsPage) or while the shared Dock service raises
    // the design-settings flag (the Stage Editor's dock page opens it here).
    Loader {
        id: settingsLoader
        active: root.active && (Ii.GlobalStates.settingsOpen || Dock.designSettingsOpen)
        sourceComponent: Component {
            PanelWindow {
                id: settingsWindow

                screen: Quickshell.primaryScreen
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Rectangle {
                    anchors.fill: parent
                    color: Ii.Appearance.colors.colScrim
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.closeSettings()
                    }
                }

                Item {
                    id: card
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.9, 1100)
                    height: Math.min(parent.height * 0.9, 800)

                    Rectangle {
                        anchors.fill: parent
                        radius: Ii.Appearance.rounding.large
                        color: Ii.Appearance.colors.colLayer1
                    }

                    Ii.DockConfig {
                        anchors.fill: parent
                        anchors.margins: 8
                    }
                }

                Ii.FocusGrab {
                    active: settingsWindow.visible
                    windows: [settingsWindow]
                    onCleared: root.closeSettings()
                }
            }
        }
    }
}
