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

    configEntryName: "clock_hori"

    readonly property real contentScale: (Config.options.background.widgets.clock_hori.widgetSize ?? 100) / 100.0
    implicitWidth: 320 * contentScale
    implicitHeight: 200 * contentScale

    // ── Time extraction (same approach as FlexClock) ──
    readonly property string hour:   DateTime.time.split(":")[0].padStart(2, "0")
    readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")

    readonly property string d0: hour.charAt(0)
    readonly property string d1: hour.charAt(1)
    readonly property string d2: minute.charAt(0)
    readonly property string d3: minute.charAt(1)

    // ── Colors (WidgetColorScheme tokens, same pattern as FlexClock) ──
    readonly property bool useAltColors: Config.options.background.widgets.clock_hori.useAltColors ?? false
    readonly property color tintSoft: useAltColors ? WidgetColorScheme.cardBgColor : WidgetColorScheme.textColorOnBg
    readonly property color tintBold: WidgetColorScheme.accentColor

    // ── Layout geometry (horizontal, 320×200) ──
    readonly property real tileW:      root.width  * 0.22
    readonly property real tileH:      root.height * 0.72
    readonly property real glyphSize:  root.height * 0.60
    readonly property real posY:       root.height * 0.14

    readonly property real pos0X:      root.width  * 0.00
    readonly property real pos1X:      root.width  * 0.17
    readonly property real pos2X:      root.width  * 0.48
    readonly property real pos3X:      root.width  * 0.65

    readonly property real colonX:     root.width  * 0.43
    readonly property real colonDotSize: root.height * 0.07
    readonly property real colonGap:   root.height * 0.08

    readonly property real fringeSize: root.height * 0.02

    // ── Fringe / stroke samples (PixelClock style) ──
    function ringSamples(count, radius) {
        let pts = [{ dx: 0, dy: 0 }]
        for (let i = 0; i < count; i++) {
            const a = (i / count) * Math.PI * 2
            pts.push({ dx: Math.cos(a) * radius, dy: Math.sin(a) * radius })
        }
        return pts
    }
    readonly property var fringeSamples: ringSamples(16, root.fringeSize)

    // ── Drop shadow ──
    StyledDropShadow {
        id: glyphShadow
        target: glyphStage
        visible: Config.options.background.widgets.enableShadows ?? false
    }

    // ── Main stage ──
    Item {
        id: glyphStage
        anchors.fill: parent

        component GlyphTile: Text {
            width: root.tileW
            height: root.tileH
            font {
                family: "Google Sans Flex"
                weight: 1000
                bold: true
                pixelSize: root.glyphSize
                variableAxes: ({ "wght": 1000 })
            }
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // ── Layer 0: d0 (H0) cut by d1, d2, d3 ──
        Item {
            id: layer0Face
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.pos0X; y: root.posY
                text: root.d0; color: root.tintSoft
            }
        }
        Item {
            id: layer0Punch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.pos1X + modelData.dx; y: root.posY + modelData.dy; text: root.d1; color: "black" }
                    GlyphTile { x: root.pos2X + modelData.dx; y: root.posY + modelData.dy; text: root.d2; color: "black" }
                    GlyphTile { x: root.pos3X + modelData.dx; y: root.posY + modelData.dy; text: root.d3; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: layer0Face
            maskSource: layer0Punch
            invert: true
            z: 0
        }

        // ── Layer 1: d1 (H1) cut by d2, d3 ──
        Item {
            id: layer1Face
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.pos1X; y: root.posY
                text: root.d1; color: root.tintBold
            }
        }
        Item {
            id: layer1Punch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.pos2X + modelData.dx; y: root.posY + modelData.dy; text: root.d2; color: "black" }
                    GlyphTile { x: root.pos3X + modelData.dx; y: root.posY + modelData.dy; text: root.d3; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: layer1Face
            maskSource: layer1Punch
            invert: true
            z: 1
        }

        // ── Layer 2: d2 (M0) cut by d3 ──
        Item {
            id: layer2Face
            anchors.fill: parent
            visible: false
            GlyphTile {
                x: root.pos2X; y: root.posY
                text: root.d2; color: root.tintBold
            }
        }
        Item {
            id: layer2Punch
            anchors.fill: parent
            visible: false
            Repeater {
                model: root.fringeSamples
                Item {
                    required property var modelData
                    anchors.fill: parent
                    GlyphTile { x: root.pos3X + modelData.dx; y: root.posY + modelData.dy; text: root.d3; color: "black" }
                }
            }
        }
        OpacityMask {
            anchors.fill: parent
            source: layer2Face
            maskSource: layer2Punch
            invert: true
            z: 2
        }

        // ── Layer 3: d3 (M1) intact ──
        GlyphTile {
            x: root.pos3X; y: root.posY
            text: root.d3; color: root.tintSoft
            z: 3
        }

        // ── Colon separator between H1 and M0 ──
        Column {
            x: root.colonX
            y: root.posY + root.tileH / 2 - height / 2
            spacing: root.colonGap
            z: 4

            Rectangle {
                width: root.colonDotSize
                height: root.colonDotSize
                radius: width / 2
                color: root.tintBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Rectangle {
                width: root.colonDotSize
                height: root.colonDotSize
                radius: width / 2
                color: root.tintBold
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }
}
