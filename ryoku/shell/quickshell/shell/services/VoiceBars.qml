pragma Singleton
import QtQuick
import Quickshell
import Ryoku.Blobs

Singleton {
    id: root

    property bool active: false
    readonly property int bars: 16
    readonly property real floor: 0.06
    readonly property list<real> levels: feed.levels

    CavaFeed {
        id: feed
        active: root.active
        bars: root.bars
        framerate: 30
        method: "pulse"
        source: Audio.source && Audio.source.name ? Audio.source.name : "auto"
        noiseFloor: root.floor
        captureActive: true
        autosens: true
        sensitivity: 100
        noiseReduction: 60
        staleMs: 120
    }
}
