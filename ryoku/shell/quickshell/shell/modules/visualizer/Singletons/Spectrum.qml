pragma Singleton
import QtQuick
import Quickshell
import Ryoku.Blobs
import shell.services

Singleton {
    id: root

    property bool active: false
    property int bars: 64
    property int fps: 60
    property int placementHolds: 0

    readonly property bool analysing: root.active
        && (!Perf.visualizerFrozen || root.placementHolds > 0)
    readonly property list<real> levels: feed.levels
    readonly property real energy: feed.energy
    readonly property bool silent: feed.silent
    readonly property bool running: feed.running

    CavaFeed {
        id: feed
        active: root.analysing
        bars: root.bars
        framerate: root.fps
        method: "pipewire"
        source: "auto"
        autosens: false
        sensitivity: 180
        noiseReduction: 45
        peakFollow: false
        staleMs: 260
    }
}
