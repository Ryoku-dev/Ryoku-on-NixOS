import QtQuick

// The hue filter: colour here is data, the one place the masthead carries it.
Row {
    id: strip

    // hueFilter: -1 none, 0-11 hue bucket, 99 grey.
    required property LibraryView view
    readonly property bool filtering: strip.view && strip.view.hueFilter !== -1
    // A narrow masthead packs the chips tighter rather than crowding the controls beside it.
    property bool compact: false

    spacing: (strip.compact ? 1 : 4) * Theme.scale
    height: 30 * Theme.scale

    Repeater {
        model: 13

        Item {
            id: cell
            required property int index
            readonly property int filterValue: index < 12 ? index : 99
            readonly property bool isSelected: strip.view && strip.view.hueFilter === filterValue
            readonly property bool isHovered: cellMouse.containsMouse

            width: (strip.compact ? 10 : 13) * Theme.scale
            height: strip.height

            // The chosen hue gets a bone ring standing off its chip.
            Rectangle {
                anchors.centerIn: chip
                width: chip.width + 6 * Theme.scale
                height: width
                radius: 4 * Theme.scale
                color: "transparent"
                border.width: 1.5 * Theme.scale
                border.color: Theme.surfaceText
                opacity: cell.isSelected ? 1 : 0
                scale: cell.isSelected ? 1 : 0.6
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                Behavior on scale { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutBack } }
            }
            Rectangle {
                id: chip
                anchors.horizontalCenter: parent.horizontalCenter
                y: (parent.height - height) * 0.5 - (cell.isHovered ? 2 : 0) * Theme.scale
                width: (strip.compact ? 8 : 11) * Theme.scale
                height: width
                radius: 2.5 * Theme.scale
                color: cell.index === 12 ? Qt.hsla(0, 0, 0.55, 1.0) : Qt.hsla(cell.index / 12.0, 0.58, 0.52, 1.0)
                opacity: (cell.isSelected || cell.isHovered || !strip.filtering) ? 1.0 : 0.32
                scale: cell.isHovered ? 1.25 : 1
                Behavior on y { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: Theme.standard } }
            }

            MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (strip.view)
                        strip.view.hueFilter = cell.isSelected ? -1 : cell.filterValue
                }
            }
        }
    }
}
