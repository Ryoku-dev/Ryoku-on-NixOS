import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets
import stage.services

/**
 * The ii dock's seven trays as cards, in the design picker's plate language:
 * a miniature screen with the tray drawn where it sits, grouped the way the
 * trays behave (off the edge, or on it).
 */
ColumnLayout {
    id: root

    property string currentValue: "floating"
    signal selected(string value)

    Layout.fillWidth: true
    spacing: Appearance.sizes.space2

    readonly property var groups: [
        {
            title: Translation.tr("Off the edge"),
            columns: 3,
            trays: [
                { value: "floating", title: Translation.tr("Floating") },
                { value: "islands", title: Translation.tr("Islands") },
                { value: "transparent", title: Translation.tr("Transparent") }
            ]
        },
        {
            title: Translation.tr("On the edge"),
            columns: 2,
            trays: [
                { value: "hug", title: Translation.tr("Hug") },
                { value: "dynamic_island", title: Translation.tr("Dynamic island") },
                { value: "full_width", title: Translation.tr("Full width") },
                { value: "full_width_concave", title: Translation.tr("Full width, rounded") }
            ]
        }
    ]

    Repeater {
        model: root.groups

        delegate: ColumnLayout {
            id: group
            required property var modelData
            Layout.fillWidth: true
            spacing: Appearance.sizes.space1

            StyledText {
                Layout.leftMargin: Appearance.sizes.space2
                text: group.modelData.title
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            GridLayout {
                Layout.fillWidth: true
                columns: group.modelData.columns
                columnSpacing: Appearance.sizes.space2
                rowSpacing: Appearance.sizes.space2

                Repeater {
                    model: group.modelData.trays
                    delegate: TrayCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        style: modelData.value
                        title: modelData.title
                        chosen: root.currentValue === modelData.value
                        onClicked: root.selected(modelData.value)
                    }
                }
            }
        }
    }

    // The selected card is the inverted plate, so everything on it reads
    // through the inverse pair, exactly as the design picker's cards do.
    component TrayCard: Rectangle {
        id: card
        property string style: ""
        property string title: ""
        property bool chosen: false
        signal clicked()

        readonly property color ink: chosen
            ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurface
        readonly property color screenFill: chosen
            ? Appearance.withAlpha(card.ink, 0.12) : Appearance.colors.colSurfaceContainerHighest
        readonly property color trayFill: chosen
            ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
        readonly property color dotFill: chosen
            ? Appearance.colors.colSecondaryContainer : Appearance.colors.colSurfaceContainerHighest

        implicitHeight: 92
        radius: Appearance.rounding.small
        color: chosen ? Appearance.colors.colSecondaryContainer
            : mouse.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
        border.width: 1
        border.color: chosen ? Appearance.colors.colSecondary
            : mouse.containsMouse ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(card)
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Appearance.sizes.space2
            spacing: Appearance.sizes.space2

            Rectangle {
                id: screen
                Layout.fillWidth: true
                implicitHeight: 44
                radius: Appearance.rounding.verysmall
                color: card.screenFill
                clip: true

                readonly property bool onEdge: card.style === "hug" || card.style === "dynamic_island"
                    || card.style === "full_width" || card.style === "full_width_concave"
                readonly property bool fullWidth: card.style === "full_width" || card.style === "full_width_concave"
                readonly property real trayHeight: 11

                // One tray, or the islands' three.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: screen.onEdge ? 0 : 5
                    spacing: 3
                    visible: card.style !== "transparent"

                    Repeater {
                        model: card.style === "islands" ? [0.36, 0.18, 0.1] : [screen.fullWidth ? 1 : 0.58]
                        delegate: Rectangle {
                            required property real modelData
                            required property int index
                            width: screen.width * modelData
                            height: screen.trayHeight
                            readonly property real round: screen.onEdge ? 0 : height / 2
                            readonly property real cap: screen.fullWidth ? 0 : (screen.onEdge ? 4 : height / 2)
                            topLeftRadius: cap
                            topRightRadius: cap
                            bottomLeftRadius: screen.fullWidth ? screen.radius : round
                            bottomRightRadius: screen.fullWidth ? screen.radius : round
                            color: card.trayFill

                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                Repeater {
                                    model: card.style === "islands" ? (index === 0 ? 4 : index === 1 ? 2 : 1) : 5
                                    Rectangle {
                                        required property int index
                                        width: 4
                                        height: 4
                                        radius: 2
                                        color: index === 2 && card.style !== "islands"
                                            ? Appearance.colors.colSecondary : card.dotFill
                                    }
                                }
                            }
                        }
                    }
                }

                // The transparent tray: only the icons, on the wallpaper.
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 7
                    spacing: 4
                    visible: card.style === "transparent"
                    Repeater {
                        model: 5
                        Rectangle {
                            required property int index
                            width: 5
                            height: 5
                            radius: 2.5
                            color: index === 2 ? Appearance.colors.colSecondary : card.trayFill
                        }
                    }
                }

                // Concave joins: the island's flare where it meets the edge,
                // the rounded screen corners where the full-width tray runs
                // into them.
                Repeater {
                    model: card.style === "dynamic_island" || card.style === "full_width_concave" ? [-1, 1] : []
                    delegate: Item {
                        id: ear
                        required property int modelData
                        readonly property real r: 5
                        readonly property real trayWidth: card.style === "dynamic_island" ? screen.width * 0.58 : screen.width
                        width: r
                        height: r
                        clip: true
                        y: card.style === "dynamic_island" ? screen.height - r : screen.height - screen.trayHeight - r
                        x: card.style === "dynamic_island"
                            ? (modelData < 0 ? (screen.width - trayWidth) / 2 - r : (screen.width + trayWidth) / 2)
                            : (modelData < 0 ? 0 : screen.width - r)
                        Rectangle {
                            anchors.fill: parent
                            color: card.trayFill
                        }
                        Rectangle {
                            width: ear.r * 2
                            height: ear.r * 2
                            radius: ear.r
                            color: card.screenFill
                            x: card.style === "dynamic_island" ? (ear.modelData < 0 ? -ear.r : 0) : (ear.modelData < 0 ? 0 : -ear.r)
                            y: -ear.r
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.space1
                StyledText {
                    Layout.fillWidth: true
                    text: card.title
                    color: card.ink
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }
                MaterialSymbol {
                    visible: card.chosen
                    text: "check_circle"
                    iconSize: 16
                    fill: 1
                    color: card.ink
                }
            }
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }
    }
}
