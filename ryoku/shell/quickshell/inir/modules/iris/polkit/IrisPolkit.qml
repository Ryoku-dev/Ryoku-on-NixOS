pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import inir
import inir.modules.common
import shell.services as Ryoku

// The Ryoku daemon is the machine's single PolicyKit agent
// (RYOKU_POLKIT_AGENT=1); this surface only renders its live PAM prompt in the
// iRiS look and collects the answer, so it registers no second agent. shell.qml
// holds the stock Ryoku island back while the iRiS bar style is active, so only
// this one is on screen.
Scope {
    id: root
    property var targetScreen: null

    Connections {
        target: Ryoku.Polkit
        function onActiveChanged(): void {
            root.targetScreen = Ryoku.Polkit.active ? GlobalStates.focusedScreen : null
        }
    }

    Loader {
        active: Ryoku.Polkit.active
        sourceComponent: PanelWindow {
            screen: root.targetScreen ?? GlobalStates.focusedScreen

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            color: "transparent"
            WlrLayershell.namespace: "quickshell:iris-polkit"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            IrisPolkitContent { anchors.fill: parent }
        }
    }
}
