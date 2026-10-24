import QtQuick

/*
 * The surface every Karuma sheet and menu sits on: paper, a hairline edge, one
 * radius and a soft lift. Children go inside the frame; colours come from the
 * palette, so a Matugen change retints it with the rest of the bar.
 */
Item {
    id: root

    required property var pal
    property real k: 1
    property real padding: 16
    default property alias content: body.data
    readonly property real radius: Math.round(pal.radiusL * k)
    readonly property real inner: Math.round(padding * k)

    // Soft shadow: stacked, increasingly wide translucent layers.
    Repeater {
        model: 3
        Rectangle {
            required property int index
            readonly property real grow: (index + 1) * root.k * 3
            x: -grow
            y: -grow + root.k * 4
            width: root.width + 2 * grow
            height: root.height + 2 * grow
            radius: root.radius + grow
            color: Qt.rgba(0, 0, 0, root.pal.shadowAlpha * [0.5, 0.28, 0.14][index])
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.pal.paper
        border.width: 1
        border.color: root.pal.line
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.inner
    }
}
