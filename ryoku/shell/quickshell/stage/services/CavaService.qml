pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import shell.services as ShellServices

Singleton {
    id: root

    readonly property bool active: Mpris.players.values.some(player => player?.isPlaying === true)
    readonly property list<real> visualizerPoints: ShellServices.AudioBars.levels

    function updateOwnership(): void {
        ShellServices.AudioBars.setActive(root, root.active);
    }

    onActiveChanged: root.updateOwnership()
    Component.onCompleted: root.updateOwnership()
    Component.onDestruction: ShellServices.AudioBars.setActive(root, false)
}
