pragma ComponentBehavior: Bound

import QtQuick

// A tile: a glyph badge, a label and a detail line. Used by the menu sheet and
// the quick settings toggles. `selected` is the "on" state (seal-tinted).
Rectangle {
    id: root

    property string glyph: ""
    property string label: ""
    property string detail: ""
    property bool selected: false
    property bool disabled: false
    property real uiScale: 1
    // The palette bridge (KarumaPalette); every colour and face follows it.
    property var pal: null
    property color ink: pal ? pal.ink : "#f0e5d3"
    property color mutedInk: pal ? pal.inkMuted : "#b5a691"
    property color accent: pal ? pal.seal : "#c74637"
    property color accentInk: pal ? pal.onSeal : "#1c1713"
    readonly property string jpFamily: pal ? pal.jp : "serif"
    readonly property string monoFamily: pal ? pal.mono : "monospace"
    readonly property string textFamily: pal ? pal.text : "sans-serif"

    // Hover fades follow the Animations switch.
    property bool animate: pal ? pal.animate : true

    signal activated()

    function px(v) { return Math.round(v * root.uiScale) }

    implicitWidth: px(176)
    implicitHeight: px(54)
    radius: px(pal ? pal.radiusM : 10)
    activeFocusOnTab: !root.disabled
    color: root.selected ? (pal ? pal.sealTint : "#33c74637")
        : (mouse.pressed ? (pal ? pal.press : "#22ffffff")
        : (mouse.containsMouse ? (pal ? pal.hover : "#15ffffff") : (pal ? pal.raised : "#0dffffff")))
    border.width: 1
    border.color: root.activeFocus ? root.accent
        : (root.selected ? (pal ? pal.sealEdge : root.accent)
        : (mouse.containsMouse ? (pal ? pal.lineStrong : "#55ffffff") : (pal ? pal.lineSoft : "#22ffffff")))
    opacity: root.disabled ? 0.42 : 1

    Behavior on color { enabled: root.animate; ColorAnimation { duration: 120 } }
    Behavior on border.color { enabled: root.animate; ColorAnimation { duration: 120 } }

    Rectangle {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: root.px(10)
        anchors.verticalCenter: parent.verticalCenter
        width: root.px(32)
        height: width
        radius: root.px(pal ? pal.radiusS + 2 : 8)
        color: root.selected ? root.accent : (pal ? pal.hover : "#15ffffff")
        Behavior on color { enabled: root.animate; ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: root.selected ? root.accentInk : root.ink
            font.family: root.jpFamily
            font.pixelSize: root.px(16)
        }
    }

    Column {
        anchors.left: badge.right
        anchors.leftMargin: root.px(10)
        anchors.right: parent.right
        anchors.rightMargin: root.px(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.px(2)

        Text {
            width: parent.width
            text: root.label
            color: root.ink
            font.family: root.monoFamily
            font.pixelSize: root.px(10)
            font.bold: true
            font.letterSpacing: root.px(0.8)
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            visible: root.detail.length > 0
            text: root.detail
            color: root.mutedInk
            font.family: root.textFamily
            font.pixelSize: root.px(10)
            elide: Text.ElideRight
        }
    }

    Keys.onReturnPressed: if (!root.disabled) root.activated()
    Keys.onEnterPressed: if (!root.disabled) root.activated()
    Keys.onSpacePressed: if (!root.disabled) root.activated()

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.disabled
        cursorShape: root.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
