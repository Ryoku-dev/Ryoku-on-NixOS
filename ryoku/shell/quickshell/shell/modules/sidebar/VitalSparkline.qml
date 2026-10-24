pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Blobs
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property var monitor
    required property bool active
    required property real s
    property var channels: ["cpu"]
    property var colors: [Tokens.sun]
    property bool fill: true
    property bool showGrid: false
    property bool detailPoints: false
    property real lineWidth: Tokens.border * s

    clip: true

    SystemGraph {
        anchors.fill: parent
        source: root.monitor
        active: root.active
        animated: !Tokens.reduceMotion && !Motion.reduce
        channels: root.channels
        colors: root.colors
        fill: root.fill
        showGrid: root.showGrid
        detailPoints: root.detailPoints
        gridColor: Tokens.lineSoft
        lineWidth: root.lineWidth
    }
}
