pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell.Io
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property real s
    required property var screen
    required property bool active
    property bool linked: false
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce
    readonly property int displayCount: (Devices.backlightAvailable ? 1 : 0) + (Devices.ddcMonitors || []).length
    readonly property string internalOutput: {
        const outputs = Wm.outputs || [];
        for (let i = 0; i < outputs.length; ++i) {
            const name = outputs[i] && outputs[i].name ? String(outputs[i].name) : "";
            if (/eDP|LVDS|DSI/i.test(name))
                return name;
        }
        return I18n.tr("Built-in display");
    }
    signal levelChanged(string outputName, int percent)

    implicitHeight: body.implicitHeight

    function applyLinked(source, percent): void {
        if (!root.linked)
            return;
        const clamped = Math.max(1, Math.min(100, Math.round(percent)));
        if (Devices.backlightAvailable && source !== "internal")
            internalRow.setLinkedPercent(clamped);
        for (let i = 0; i < ddcRepeater.count; ++i) {
            const row = ddcRepeater.itemAt(i);
            if (row && row.bus !== source)
                row.setLinkedPercent(clamped);
        }
    }

    onActiveChanged: {
        if (active) {
            Devices.startProbes(root);
        } else {
            internalRow.flush();
            for (let i = 0; i < ddcRepeater.count; ++i) {
                const row = ddcRepeater.itemAt(i);
                if (row)
                    row.flush();
            }
            Devices.stopProbes(root);
        }
    }
    Component.onCompleted: if (active) Devices.startProbes(root)
    Component.onDestruction: {
        internalRow.flush();
        for (let i = 0; i < ddcRepeater.count; ++i) {
            const row = ddcRepeater.itemAt(i);
            if (row)
                row.flush();
        }
        Devices.stopProbes(root);
    }

    Column {
        id: body
        width: parent.width
        spacing: Tokens.s2 * root.s

        Rectangle {
            width: parent.width
            height: Tokens.border
            color: Tokens.lineSoft
        }

        Item {
            id: internalRow
            width: parent.width
            height: Devices.backlightAvailable ? internalLevel.implicitHeight : 0
            visible: height > 0
            property int pending: -1

            function setPercent(percent, broadcast): void {
                const value = Math.max(1, Math.min(100, Math.round(percent)));
                Devices.backlightPct = value;
                pending = value;
                internalCommit.restart();
                root.levelChanged(root.internalOutput, value);
                if (broadcast)
                    root.applyLinked("internal", value);
            }
            function setLinkedPercent(percent): void { setPercent(percent, false); }
            function flush(): void {
                if (pending >= 0)
                    Devices.setBacklight(pending);
                pending = -1;
                internalCommit.stop();
            }

            LevelSlider {
                id: internalLevel
                width: parent.width
                s: root.s
                label: root.internalOutput
                glyph: value < 0.34 ? "brightness_low" : value < 0.67 ? "brightness_medium" : "brightness_high"
                value: Math.max(0, Devices.backlightPct) / 100
                from: 0.01
                available: Devices.backlightAvailable
                expandable: false
                onAdjusted: value => internalRow.setPercent(value * 100, true)
            }
            Timer {
                id: internalCommit
                interval: 90
                onTriggered: internalRow.flush()
            }
        }

        Repeater {
            id: ddcRepeater
            model: Devices.ddcMonitors || []
            delegate: Item {
                id: monitorRow
                required property var modelData
                readonly property string bus: String(modelData.bus)
                readonly property string outputName: String(modelData.label)
                property int percent: -1
                property int pending: -1
                width: body.width
                height: monitorLevel.implicitHeight

                function readLevel(): void {
                    if (!root.active || readProcess.running)
                        return;
                    readProcess.command = ["timeout", "3", "ddcutil", "getvcp", "10", "--brief", "--bus", monitorRow.bus];
                    readProcess.running = true;
                }
                function setPercent(value, broadcast): void {
                    const next = Math.max(5, Math.min(100, Math.round(value)));
                    monitorRow.percent = next;
                    monitorRow.pending = next;
                    commit.restart();
                    root.levelChanged(monitorRow.outputName, next);
                    if (broadcast)
                        root.applyLinked(monitorRow.bus, next);
                }
                function setLinkedPercent(value): void { setPercent(value, false); }
                function flush(): void {
                    if (monitorRow.pending >= 0)
                        Devices.setBrightness(monitorRow.bus, monitorRow.pending);
                    monitorRow.pending = -1;
                    commit.stop();
                }
                function syncActive(): void {
                    if (root.active)
                        monitorRow.readLevel();
                    else {
                        readProcess.running = false;
                        monitorRow.flush();
                    }
                }

                Component.onCompleted: monitorRow.syncActive()
                Component.onDestruction: monitorRow.flush()
                Connections {
                    target: root
                    function onActiveChanged(): void { monitorRow.syncActive(); }
                }

                LevelSlider {
                    id: monitorLevel
                    width: parent.width
                    s: root.s
                    label: monitorRow.outputName
                    glyph: value < 0.34 ? "brightness_low" : value < 0.67 ? "brightness_medium" : "brightness_high"
                    value: Math.max(0, monitorRow.percent) / 100
                    from: 0.05
                    available: monitorRow.percent >= 0
                    expandable: false
                    onAdjusted: value => monitorRow.setPercent(value * 100, true)
                }
                Timer {
                    id: commit
                    interval: 160
                    onTriggered: monitorRow.flush()
                }
                Process {
                    id: readProcess
                    stdout: StdioCollector {
                        onStreamFinished: {
                            const value = Devices.parseBrightness(text);
                            if (value >= 0) {
                                monitorRow.percent = value;
                                root.levelChanged(monitorRow.outputName, value);
                            }
                        }
                    }
                }
            }
        }

        QQC.AbstractButton {
            id: linkButton
            width: parent.width
            height: Tokens.rowH * root.s
            visible: root.displayCount > 1
            hoverEnabled: true
            Accessible.name: I18n.tr("Link displays")
            Accessible.checked: root.linked
            onClicked: root.linked = !root.linked
            background: Rectangle {
                radius: Tokens.radius * root.s
                color: linkButton.down ? Tokens.tint16 : linkButton.hovered ? Tokens.tint5 : "transparent"
                border.width: linkButton.visualFocus ? Tokens.border : 0
                border.color: Tokens.bone
                Behavior on color {
                    enabled: root.motionAllowed
                    ColorAnimation { duration: Tokens.snap }
                }
            }
            contentItem: Item {
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Link displays")
                    color: Tokens.ink
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall * root.s
                    font.weight: Font.Medium
                }
                Rectangle {
                    id: switchTrack
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.ctlH * 2 * root.s
                    height: Tokens.ctlH * root.s
                    radius: Tokens.radius * root.s
                    color: root.linked ? Tokens.tint16 : Tokens.tint5
                    border.width: Tokens.border
                    border.color: root.linked ? Tokens.lineStrong : Tokens.line
                    Rectangle {
                        width: (Tokens.ctlH - Tokens.s2) * root.s
                        height: width
                        y: Tokens.s1 * root.s
                        x: root.linked ? parent.width - width - Tokens.s1 * root.s : Tokens.s1 * root.s
                        radius: Tokens.radius * root.s
                        color: root.linked ? Tokens.ink : Tokens.inkDim
                        Behavior on x {
                            enabled: root.motionAllowed
                            NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                        }
                    }
                    Behavior on color {
                        enabled: root.motionAllowed
                        ColorAnimation { duration: Tokens.snap }
                    }
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
}