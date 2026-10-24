pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_flex"

    readonly property real contentScale: (Config.options.background.widgets.clock_flex.widgetSize ?? 100) / 100.0
    implicitWidth: 240 * contentScale
    implicitHeight: 240 * contentScale

    // Time extraction
    readonly property string hour: DateTime.time.split(":")[0].padStart(2, "0")
    readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")

    readonly property string d0: hour.charAt(0)
    readonly property string d1: hour.charAt(1)
    readonly property string d2: minute.charAt(0)
    readonly property string d3: minute.charAt(1)

    // Colors from WidgetColorScheme (Diagonal pattern)
    readonly property bool useAltColors: Config.options.background.widgets.clock_flex.useAltColors ?? false
    readonly property color colorDiagonalA: useAltColors ? WidgetColorScheme.cardBgColor : WidgetColorScheme.textColorOnBg
    readonly property color colorDiagonalB: WidgetColorScheme.accentColor

    // Stroke thickness around upper elements (die-cut margin)
    readonly property real strokeWidth: root.width * 0.020

    // Tight grid 2x2 cell dimensions
    readonly property real cellW: root.width * 0.66
    readonly property real cellH: root.height * 0.66

    // Cell positions (fine-tuned spacing)
    readonly property real col0X: root.width * 0.00
    readonly property real col1X: root.width * 0.30
    readonly property real row0Y: root.height * -0.04
    readonly property real row1Y: root.height * 0.42

    readonly property real glyphPixelSize: root.height * 0.66

    // Smooth circle sample offset model for clean outline masks without sharp corner artifacts
    readonly property var strokeOffsets: [
        { dx: 0, dy: 0 },
        { dx: -strokeWidth, dy: 0 },
        { dx: strokeWidth, dy: 0 },
        { dx: 0, dy: -strokeWidth },
        { dx: 0, dy: strokeWidth },
        { dx: -strokeWidth * 0.92, dy: -strokeWidth * 0.38 },
        { dx: strokeWidth * 0.92, dy: -strokeWidth * 0.38 },
        { dx: -strokeWidth * 0.92, dy: strokeWidth * 0.38 },
        { dx: strokeWidth * 0.92, dy: strokeWidth * 0.38 },
        { dx: -strokeWidth * 0.38, dy: -strokeWidth * 0.92 },
        { dx: strokeWidth * 0.38, dy: -strokeWidth * 0.92 },
        { dx: -strokeWidth * 0.38, dy: strokeWidth * 0.92 },
        { dx: strokeWidth * 0.38, dy: strokeWidth * 0.92 },
        { dx: -strokeWidth * 0.707, dy: -strokeWidth * 0.707 },
        { dx: strokeWidth * 0.707, dy: -strokeWidth * 0.707 },
        { dx: -strokeWidth * 0.707, dy: strokeWidth * 0.707 },
        { dx: strokeWidth * 0.707, dy: strokeWidth * 0.707 }
    ]

    StyledDropShadow {
        id: bgShadow
        target: container
        visible: Config.options.background.widgets.enableShadows ?? false
    }

    Item {
        id: container
        anchors.fill: parent

        // Reusable Digit template
        component Digit: Text {
            width: root.cellW
            height: root.cellH
            font {
                family: "Google Sans Flex"
                weight: 1000
                bold: true
                pixelSize: root.glyphPixelSize
                variableAxes: ({ "wght": 1000 })
            }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // =============================================================
        // LAYER 1: BASE LAYER (d0 - Top-Left H1) [z: 0]
        // Cut out by: d1, d2, d3
        // =============================================================
        Item {
            id: layer0Source
            anchors.fill: parent
            visible: false

            Digit {
                x: root.col0X
                y: root.row0Y
                text: root.d0
                color: root.colorDiagonalA
            }
        }

        Item {
            id: layer0Mask
            anchors.fill: parent
            visible: false

            Repeater {
                model: root.strokeOffsets
                Item {
                    id: strokeDel0
                    required property var modelData
                    anchors.fill: parent

                    // Cutout d1
                    Digit {
                        x: root.col1X + strokeDel0.modelData.dx
                        y: root.row0Y + strokeDel0.modelData.dy
                        text: root.d1
                        color: "black"
                    }
                    // Cutout d2
                    Digit {
                        x: root.col0X + strokeDel0.modelData.dx
                        y: root.row1Y + strokeDel0.modelData.dy
                        text: root.d2
                        color: "black"
                    }
                    // Cutout d3
                    Digit {
                        x: root.col1X + strokeDel0.modelData.dx
                        y: root.row1Y + strokeDel0.modelData.dy
                        text: root.d3
                        color: "black"
                    }
                }
            }
        }

        OpacityMask {
            anchors.fill: parent
            source: layer0Source
            maskSource: layer0Mask
            invert: true
            z: 0
        }

        // =============================================================
        // LAYER 2: TOP-RIGHT DIGIT (d1 - Top-Right H2) [z: 1]
        // Cut out by: d2, d3
        // =============================================================
        Item {
            id: layer1Source
            anchors.fill: parent
            visible: false

            Digit {
                x: root.col1X
                y: root.row0Y
                text: root.d1
                color: root.colorDiagonalB
            }
        }

        Item {
            id: layer1Mask
            anchors.fill: parent
            visible: false

            Repeater {
                model: root.strokeOffsets
                Item {
                    id: strokeDel1
                    required property var modelData
                    anchors.fill: parent

                    // Cutout d2
                    Digit {
                        x: root.col0X + strokeDel1.modelData.dx
                        y: root.row1Y + strokeDel1.modelData.dy
                        text: root.d2
                        color: "black"
                    }
                    // Cutout d3
                    Digit {
                        x: root.col1X + strokeDel1.modelData.dx
                        y: root.row1Y + strokeDel1.modelData.dy
                        text: root.d3
                        color: "black"
                    }
                }
            }
        }

        OpacityMask {
            anchors.fill: parent
            source: layer1Source
            maskSource: layer1Mask
            invert: true
            z: 1
        }

        // =============================================================
        // LAYER 3: BOTTOM-LEFT DIGIT (d2 - Bottom-Left M1) [z: 2]
        // Cut out by: d3
        // =============================================================
        Item {
            id: layer2Source
            anchors.fill: parent
            visible: false

            Digit {
                x: root.col0X
                y: root.row1Y
                text: root.d2
                color: root.colorDiagonalB
            }
        }

        Item {
            id: layer2Mask
            anchors.fill: parent
            visible: false

            Repeater {
                model: root.strokeOffsets
                Item {
                    id: strokeDel2
                    required property var modelData
                    anchors.fill: parent

                    // Cutout d3
                    Digit {
                        x: root.col1X + strokeDel2.modelData.dx
                        y: root.row1Y + strokeDel2.modelData.dy
                        text: root.d3
                        color: "black"
                    }
                }
            }
        }

        OpacityMask {
            anchors.fill: parent
            source: layer2Source
            maskSource: layer2Mask
            invert: true
            z: 2
        }

        // =============================================================
        // LAYER 4: BOTTOM-RIGHT DIGIT (d3 - Bottom-Right M2) [z: 3]
        // Topmost element — stays 100% intact, no mask cutout
        // =============================================================
        Digit {
            x: root.col1X
            y: root.row1Y
            text: root.d3
            color: root.colorDiagonalA
            z: 3
        }
    }
}
