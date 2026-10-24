import QtQuick

// One masthead control. Emphasis is inversion: an active control turns into a bone
// plate with dark ink rather than taking an accent colour.
Item {
    id: btn

    property string label: ""
    property string glyph: ""
    property bool active: false
    property bool destructive: false
    property string tooltip: ""
    property real hpad: 10
    // A long label (a deep folder path) elides past this width; 0 never elides.
    property real maxLabelWidth: 0

    // A menu trigger carries a chevron that turns over while its list is open.
    property bool dropdown: false
    property bool expanded: false
    // The settings gear turns a little under the pointer.
    property bool spinOnHover: false

    signal triggered()

    readonly property bool hovered: hover.containsMouse
    readonly property color ink: !btn.enabled ? Theme.withAlpha(Theme.surfaceText, 0.3)
        : btn.active ? Theme.surface
        : btn.destructive ? Theme.tertiary
        : btn.hovered ? Theme.surfaceText
        : Theme.withAlpha(Theme.surfaceText, 0.74)

    implicitHeight: 30 * Theme.scale
    implicitWidth: content.implicitWidth + btn.hpad * 2 * Theme.scale

    Rectangle {
        id: face
        anchors.fill: parent
        radius: Theme.radius
        scale: hover.pressed ? 0.94 : 1
        color: btn.active ? Theme.surfaceText
             : btn.hovered && btn.enabled ? Theme.withAlpha(Theme.surfaceText, 0.09)
             : Theme.withAlpha(Theme.surfaceText, 0)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7 * Theme.scale
        scale: face.scale

        Text {
            id: glyphText
            visible: btn.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: btn.glyph
            font.family: Theme.icon
            font.pixelSize: Theme.fs(14)
            color: btn.ink
            renderType: Text.NativeRendering
            rotation: btn.spinOnHover && btn.hovered ? 60 : 0
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Behavior on rotation { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
        }
        Text {
            visible: btn.label.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            width: btn.maxLabelWidth > 0 ? Math.min(implicitWidth, btn.maxLabelWidth * Theme.scale) : implicitWidth
            elide: Text.ElideMiddle
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fs(12.5)
            color: btn.ink
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        Text {
            visible: btn.dropdown
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0140}"
            font.family: Theme.icon
            font.pixelSize: Theme.fs(13)
            color: btn.ink
            rotation: btn.expanded ? 180 : 0
            renderType: Text.NativeRendering
            Behavior on rotation { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutBack } }
        }
    }

    // A toggle that turns on, or a glyph that changes (sort order, light and dark), gets one
    // small pop so the change reads at a glance.
    SequentialAnimation {
        id: pop
        NumberAnimation { target: glyphText; property: "scale"; to: 1.3; duration: Theme.fast * 0.45; easing.type: Easing.OutQuad }
        NumberAnimation { target: glyphText; property: "scale"; to: 1; duration: Theme.fast; easing.type: Easing.OutBack; easing.overshoot: 3 }
    }
    onActiveChanged: if (btn.active && btn.visible) pop.restart()
    onGlyphChanged: if (btn.visible) pop.restart()

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.triggered()
        onExited: tipTimer.stop()
        onEntered: if (btn.tooltip.length > 0) tipTimer.restart()
    }

    Timer { id: tipTimer; interval: 550 }

    Rectangle {
        id: tip
        visible: opacity > 0.01
        opacity: (btn.hovered && btn.tooltip.length > 0 && !tipTimer.running) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        z: 50
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: (6 + (1 - tip.opacity) * -4) * Theme.scale
        width: tipText.implicitWidth + 16 * Theme.scale
        height: tipText.implicitHeight + 10 * Theme.scale
        radius: Theme.radius
        color: Theme.surfaceText
        Text {
            id: tipText
            anchors.centerIn: parent
            text: btn.tooltip
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fs(11.5)
            color: Theme.surface
            renderType: Text.NativeRendering
        }
    }
}
