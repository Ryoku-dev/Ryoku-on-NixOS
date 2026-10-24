import QtQuick

// A masthead dropdown: a trigger and the list it unfolds beneath it. The list leaves when
// the pointer has been away from both for a moment, or once a row is chosen.
Item {
    id: menu

    property string label: ""
    property string glyph: ""
    property string tooltip: ""
    property bool active: false
    property real panelWidth: 220
    property real maxRows: 12
    // Menus at the right end of the masthead open leftward so they stay on screen.
    property bool alignRight: false
    property real maxLabelWidth: 0
    // Rows declared inside a menu land in its list.
    default property alias rows: list.data

    property bool open: false
    function close() { menu.open = false }

    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight
    onVisibleChanged: if (!menu.visible) menu.open = false

    BarButton {
        id: trigger
        anchors.fill: parent
        glyph: menu.glyph
        label: menu.label
        maxLabelWidth: menu.maxLabelWidth
        tooltip: menu.open ? "" : menu.tooltip
        active: menu.active
        dropdown: true
        expanded: menu.open
        onTriggered: menu.open = !menu.open
    }

    Timer { id: closeTimer; interval: 350; onTriggered: menu.open = false }
    HoverHandler { id: triggerHover; onHoveredChanged: menu._maybeClose() }
    function _maybeClose() {
        if (!menu.open) return
        if (triggerHover.hovered || panelHover.hovered) closeTimer.stop()
        else closeTimer.restart()
    }

    Rectangle {
        id: panel
        property real reveal: menu.open ? 1 : 0
        Behavior on reveal { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutCubic } }

        visible: reveal > 0.01
        z: 80
        x: menu.alignRight ? menu.width - width : 0
        y: menu.height + 6 * Theme.scale
        width: menu.panelWidth * Theme.scale
        height: Math.min(list.implicitHeight, menu.maxRows * 30 * Theme.scale) + 12 * Theme.scale
        radius: Theme.radius
        color: Theme.withAlpha(Theme.surface, 0.985)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.55)
        opacity: reveal
        transformOrigin: Item.Top
        transform: [
            Scale { origin.y: 0; yScale: 0.92 + 0.08 * panel.reveal },
            Translate { y: (1 - panel.reveal) * -6 * Theme.scale }
        ]

        HoverHandler { id: panelHover; onHoveredChanged: menu._maybeClose() }
        // Holds clicks and hover so neither reaches the cards under the open list.
        MouseArea { anchors.fill: parent; hoverEnabled: true }

        Flickable {
            anchors.fill: parent
            anchors.margins: 6 * Theme.scale
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: parent.width
                spacing: 1
            }
        }
    }
}
