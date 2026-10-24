import QtQuick

/*
 * A level control: glyph (a mute button when `glyphIsButton`), slider, readout.
 * While it is held (and a moment after) it shows the value being dragged, so a
 * reading that lags behind the system never makes the handle jump back under
 * the pointer. Shared by the quick settings menu and the Sound sheet.
 */
Item {
    id: lv

    required property var pal
    property real k: 1
    property string glyph: ""
    property real level: 0
    property string readout: ""
    property bool urgent: false
    property bool glyphIsButton: false
    property real minLevel: 0
    property real local: 0
    readonly property real shown: (drag.pressed || hold.running) ? lv.local : lv.level
    readonly property color accent: lv.urgent ? lv.pal.urgent : lv.pal.seal

    signal moved(real level)
    signal glyphClicked()

    function px(v) { return Math.round(v * lv.k) }

    width: parent ? parent.width : 100
    height: px(36)

    Timer { id: hold; interval: 900 }

    function take(x) {
        const v = Math.max(lv.minLevel, Math.min(1, x / Math.max(1, track.width)));
        lv.local = v;
        hold.restart();
        lv.moved(v);
    }

    Rectangle {
        id: gbox
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: lv.px(32)
        height: width
        radius: lv.px(lv.pal.radiusM)
        color: lv.glyphIsButton && gArea.pressed ? lv.pal.press
            : (lv.glyphIsButton && gArea.containsMouse ? lv.pal.hover : lv.pal.raised)
        border.width: 1
        border.color: lv.glyphIsButton && gArea.containsMouse ? lv.pal.lineStrong : lv.pal.lineSoft
        Behavior on color { enabled: lv.pal.animate; ColorAnimation { duration: 110 } }
        Text {
            anchors.centerIn: parent
            text: lv.glyph
            color: lv.urgent ? lv.pal.urgent : lv.pal.ink
            font.family: lv.pal.jp
            font.pixelSize: lv.px(15)
        }
        MouseArea {
            id: gArea
            anchors.fill: parent
            enabled: lv.glyphIsButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: lv.glyphClicked()
        }
    }

    Text {
        id: value
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: lv.px(40)
        horizontalAlignment: Text.AlignRight
        text: lv.readout
        color: lv.urgent ? lv.pal.urgent : lv.pal.ink
        font.family: lv.pal.mono
        font.pixelSize: lv.px(10.5)
        font.bold: true
    }

    Item {
        id: track
        anchors.left: gbox.right
        anchors.right: value.left
        anchors.leftMargin: lv.px(12)
        anchors.rightMargin: lv.px(10)
        anchors.verticalCenter: parent.verticalCenter
        height: lv.px(28)

        Rectangle {
            id: rail
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: lv.px(6)
            radius: height / 2
            color: lv.pal.hover
            border.width: 1
            border.color: lv.pal.lineSoft
        }
        Rectangle {
            anchors.left: rail.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(height, parent.width * lv.shown)
            height: rail.height
            radius: height / 2
            color: lv.accent
        }
        Rectangle {
            id: knob
            x: Math.max(0, Math.min(parent.width - width, parent.width * lv.shown - width / 2))
            anchors.verticalCenter: parent.verticalCenter
            width: lv.px(drag.pressed ? 16 : 14)
            height: width
            radius: width / 2
            color: lv.pal.paper
            border.width: lv.px(2)
            border.color: lv.accent
            Behavior on width { enabled: lv.pal.animate; NumberAnimation { duration: 90 } }
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => lv.take(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) lv.take(mouse.x); }
            onWheel: (wheel) => {
                lv.local = lv.shown;
                const step = wheel.angleDelta.y > 0 ? 0.02 : -0.02;
                lv.local = Math.max(lv.minLevel, Math.min(1, lv.local + step));
                hold.restart();
                lv.moved(lv.local);
            }
        }
    }
}
