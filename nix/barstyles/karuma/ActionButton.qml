import QtQuick

// A compact button for sheet actions. `primary` fills with the seal colour.
Rectangle {
    id: root

    required property var pal
    property real k: 1
    property string text: ""
    property string glyph: ""
    property bool primary: false
    property bool disabled: false

    signal activated()

    function px(v) { return Math.round(v * root.k) }

    implicitHeight: px(32)
    implicitWidth: Math.max(px(32), content.implicitWidth + px(24))
    radius: px(pal.radiusM)
    activeFocusOnTab: !disabled
    opacity: disabled ? 0.42 : 1
    color: primary
        ? (area.pressed ? Qt.darker(pal.seal, 1.12) : (area.containsMouse ? Qt.lighter(pal.seal, 1.1) : pal.seal))
        : (area.pressed ? pal.press : (area.containsMouse ? pal.hover : pal.raised))
    border.width: 1
    border.color: activeFocus ? pal.seal : (primary ? "transparent" : (area.containsMouse ? pal.lineStrong : pal.line))
    Behavior on color { enabled: pal.animate; ColorAnimation { duration: 110 } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: root.px(7)
        Text {
            visible: root.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            color: root.primary ? root.pal.onSeal : root.pal.ink
            font.family: root.pal.mono
            font.pixelSize: root.px(12)
        }
        Text {
            visible: root.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.primary ? root.pal.onSeal : root.pal.ink
            font.family: root.pal.mono
            font.pixelSize: root.px(10)
            font.bold: true
            font.letterSpacing: root.px(1)
        }
    }

    Keys.onReturnPressed: if (!root.disabled) root.activated()
    Keys.onEnterPressed: if (!root.disabled) root.activated()
    Keys.onSpacePressed: if (!root.disabled) root.activated()

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.disabled
        cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
