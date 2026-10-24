pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import inir.services
import inir.modules.common

Singleton {
    id: root

    property bool available: true
    property bool enabled: true
    property string strength: "balanced"
    property real noise: 0.02
    property real saturation: 1.5
    property var elsewhere: []
    // Ryoku's window-manager seam decides whether compositor blur exists at
    // all; the niri config probe only refines it where the seam allows it.
    readonly property bool usable: CompositorService.compositorBlur && root.available && root.enabled

    function reload(): void {
        if (CompositorService.compositorBlur && !reader.running) reader.running = true
    }
    Component.onCompleted: root.reload()

    Process {
        id: reader
        command: ["python3", Directories.payloadPath("scripts/niri-config.py"), "get-blur"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const state = JSON.parse(text)
                    if (state.error) return
                    root.available = state.available
                    root.enabled = state.enabled
                    root.strength = state.strength
                    root.noise = state.noise
                    root.saturation = state.saturation
                    root.elsewhere = state.elsewhere ?? []
                } catch (e) {}
            }
        }
    }
}
