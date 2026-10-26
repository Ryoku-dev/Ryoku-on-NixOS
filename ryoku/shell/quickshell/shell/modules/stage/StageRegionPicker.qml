pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

SettingCard {
    id: picker

    required property string wallpaperUrl
    property bool interactive: true
    property real nx: 0
    property real ny: 0
    property real nw: 0
    property real nh: 0
    property real anchorNX: 0
    property real anchorNY: 0

    signal canceled()
    signal chosen(real nx, real ny, real nw, real nh)

    width: parent ? parent.width : 0
    onVisibleChanged: if (visible) {
        picker.nx = 0;
        picker.ny = 0;
        picker.nw = 0;
        picker.nh = 0;
    }
    title: I18n.tr("CHOOSE WHAT TO CUT")
    kana: "選"
    collapsible: false

    readonly property bool validBox: picker.nw >= 0.02 && picker.nh >= 0.02

    function clamp(value) {
        return Math.max(0, Math.min(1, value));
    }

    function normalizedX(px) {
        return picker.clamp((px - wallImage.paintOffsetX) / Math.max(1, wallImage.paintedWidth));
    }

    function normalizedY(py) {
        return picker.clamp((py - wallImage.paintOffsetY) / Math.max(1, wallImage.paintedHeight));
    }

    function beginBox(px, py) {
        if (!wallImage.insidePaint(px, py)) return false;
        picker.anchorNX = picker.normalizedX(px);
        picker.anchorNY = picker.normalizedY(py);
        picker.nx = picker.anchorNX;
        picker.ny = picker.anchorNY;
        picker.nw = 0;
        picker.nh = 0;
        return true;
    }

    function moveBox(px, py) {
        const x = picker.normalizedX(px);
        const y = picker.normalizedY(py);
        picker.nx = Math.min(picker.anchorNX, x);
        picker.ny = Math.min(picker.anchorNY, y);
        picker.nw = Math.abs(x - picker.anchorNX);
        picker.nh = Math.abs(y - picker.anchorNY);
    }

    SettingRow {
        width: parent.width
        label: I18n.tr("Draw a box on the wallpaper")
        desc: I18n.tr("Drag a box around one thing. Whatever stands out inside it is cut out.")
        block: true

        Column {
            width: parent.width
            spacing: Tokens.s3

            Item {
                width: parent.width
                height: Math.max(220, Math.min(420, width * 0.62))
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: Tokens.paper
                    border.width: Tokens.border
                    border.color: Tokens.line
                    radius: Tokens.radius
                }

                Image {
                    id: wallImage
                    anchors.fill: parent
                    anchors.margins: Tokens.border
                    source: picker.wallpaperUrl
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width
                    sourceSize.height: height

                    readonly property real paintOffsetX: (width - paintedWidth) / 2
                    readonly property real paintOffsetY: (height - paintedHeight) / 2
                    function insidePaint(px, py) {
                        return status === Image.Ready
                            && px >= paintOffsetX && px <= paintOffsetX + paintedWidth
                            && py >= paintOffsetY && py <= paintOffsetY + paintedHeight;
                    }

                    Rectangle {
                        visible: picker.nw > 0 && picker.nh > 0
                        x: wallImage.paintOffsetX
                        y: wallImage.paintOffsetY
                        width: wallImage.paintedWidth
                        height: picker.ny * wallImage.paintedHeight
                        color: Qt.rgba(0, 0, 0, 0.56)
                    }
                    Rectangle {
                        visible: picker.nw > 0 && picker.nh > 0
                        x: wallImage.paintOffsetX
                        y: wallImage.paintOffsetY + (picker.ny + picker.nh) * wallImage.paintedHeight
                        width: wallImage.paintedWidth
                        height: Math.max(0, (1 - picker.ny - picker.nh) * wallImage.paintedHeight)
                        color: Qt.rgba(0, 0, 0, 0.56)
                    }
                    Rectangle {
                        visible: picker.nw > 0 && picker.nh > 0
                        x: wallImage.paintOffsetX
                        y: wallImage.paintOffsetY + picker.ny * wallImage.paintedHeight
                        width: picker.nx * wallImage.paintedWidth
                        height: picker.nh * wallImage.paintedHeight
                        color: Qt.rgba(0, 0, 0, 0.56)
                    }
                    Rectangle {
                        visible: picker.nw > 0 && picker.nh > 0
                        x: wallImage.paintOffsetX + (picker.nx + picker.nw) * wallImage.paintedWidth
                        y: wallImage.paintOffsetY + picker.ny * wallImage.paintedHeight
                        width: Math.max(0, (1 - picker.nx - picker.nw) * wallImage.paintedWidth)
                        height: picker.nh * wallImage.paintedHeight
                        color: Qt.rgba(0, 0, 0, 0.56)
                    }
                    Rectangle {
                        visible: picker.nw > 0 && picker.nh > 0
                        x: wallImage.paintOffsetX + picker.nx * wallImage.paintedWidth
                        y: wallImage.paintOffsetY + picker.ny * wallImage.paintedHeight
                        width: picker.nw * wallImage.paintedWidth
                        height: picker.nh * wallImage.paintedHeight
                        color: "transparent"
                        border.width: 2
                        border.color: Tokens.bone
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        cursorShape: Qt.CrossCursor
                        // preventStealing keeps the parent Flickable from taking vertical box drags.
                        preventStealing: true
                        property bool drawing: false
                        onPressed: mouse => {
                            dragArea.drawing = picker.beginBox(mouse.x, mouse.y);
                            mouse.accepted = dragArea.drawing;
                        }
                        onPositionChanged: mouse => {
                            if (dragArea.drawing) picker.moveBox(mouse.x, mouse.y);
                        }
                        onReleased: mouse => {
                            if (dragArea.drawing) picker.moveBox(mouse.x, mouse.y);
                            dragArea.drawing = false;
                        }
                        onCanceled: dragArea.drawing = false
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: Tokens.s2

                Btn {
                    text: I18n.tr("Cancel")
                    compact: true
                    onAct: picker.canceled()
                }
                Btn {
                    text: I18n.tr("Cut this area")
                    compact: true
                    primary: true
                    armed: picker.validBox && picker.interactive
                    onAct: picker.chosen(picker.nx, picker.ny, picker.nw, picker.nh)
                }
            }
        }
    }
}
