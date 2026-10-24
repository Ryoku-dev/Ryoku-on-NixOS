pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property var monitor
    required property real s

    function blendColor(from, to, amount): color {
        const t = Math.max(0, Math.min(1, amount));
        return Qt.rgba(from.r + (to.r - from.r) * t,
                       from.g + (to.g - from.g) * t,
                       from.b + (to.b - from.b) * t,
                       from.a + (to.a - from.a) * t);
    }

    function loadColor(load): color {
        if (load <= 50)
            return Tokens.inkDim;
        if (load >= 80)
            return Tokens.sun;
        return root.blendColor(Tokens.inkDim, Tokens.sun, (load - 50) / 30);
    }

    QtObject {
        id: layout

        readonly property int count: Math.max(0, root.monitor.coreCount)
        readonly property bool available: root.monitor.cpuAvailable && count > 0
        readonly property int rowCount: count > 8 ? 2 : 1
        readonly property int columnCount: Math.max(1, Math.ceil(count / rowCount))
        readonly property real gap: Tokens.s1 * root.s
        readonly property real cellWidth: (root.width - gap * (columnCount - 1)) / columnCount
        readonly property real cellHeight: (root.height - gap * (rowCount - 1)) / rowCount
    }

    implicitHeight: layout.rowCount * (Tokens.s5 + Tokens.s1) * s
                    + (layout.rowCount - 1) * Tokens.s1 * s
    clip: true

    Grid {
        visible: layout.available
        anchors.fill: parent
        columns: layout.columnCount
        columnSpacing: layout.gap
        rowSpacing: layout.gap

        Repeater {
            model: layout.count

            delegate: Item {
                id: core
                required property int index
                width: layout.cellWidth
                height: layout.cellHeight

                readonly property real load: {
                    const loads = root.monitor.coreLoads;
                    if (!loads || core.index >= loads.length || !isFinite(loads[core.index]))
                        return 0;
                    return Math.max(0, Math.min(100, loads[core.index]));
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: Math.max(2 * root.s, parent.width * 0.5)
                    height: parent.height
                    radius: width / 2
                    color: Tokens.tint10
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: Math.max(2 * root.s, parent.width * 0.5)
                    height: Math.max(width, parent.height * core.load / 100)
                    radius: width / 2
                    color: root.loadColor(core.load)

                    Behavior on height {
                        enabled: !Tokens.reduceMotion && !Motion.reduce
                        NumberAnimation { duration: root.monitor.samplePeriodMs; easing.type: Easing.Linear }
                    }
                }
            }
        }
    }

    Text {
        visible: !layout.available
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: I18n.tr("—")
        color: Tokens.inkFaint
        font.family: Tokens.ui
        font.pixelSize: Tokens.fSmall * root.s
        elide: Text.ElideRight
    }
}
