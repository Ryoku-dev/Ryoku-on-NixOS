pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import inir
import inir.services
import inir.modules.iris.style
import inir.modules.iris.components

ClippingRectangle {
    id: root
    radius: IrisStyle.radiusCard
    color: IrisStyle.fillQuiet
    IrisWallpaperView {
        live: false
        anchors.fill: parent
        screen: GlobalStates.focusedScreen
        decodeSize: Qt.size(Math.round(Math.max(1, root.width) * 1.2), 0)
        opacity: ready ? 1 : 0
    }
}
