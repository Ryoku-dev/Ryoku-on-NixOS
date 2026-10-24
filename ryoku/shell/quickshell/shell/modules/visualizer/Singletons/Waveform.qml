pragma Singleton
import QtQuick
import Quickshell
import Ryoku.Blobs

Singleton {
    id: root

    property bool active: false
    readonly property list<real> samples: capture.samples
    readonly property bool running: capture.running
    readonly property bool silent: capture.silent

    WaveCapture {
        id: capture
        active: root.active
    }
}
