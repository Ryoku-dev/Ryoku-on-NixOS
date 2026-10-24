import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import stage
import stage.services
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
AbstractBackgroundWidget {
    id: root

    configEntryName: "pc_battery_bars"
    readonly property bool showPercentage: Config.options.background.widgets.pc_battery_bars.showPercentage ?? true
    readonly property bool showStatus: Config.options.background.widgets.pc_battery_bars.showStatus ?? true

    implicitWidth: 240
    implicitHeight: 240

    // PC Battery system info
    readonly property real batteryPct: Math.round((Battery.percentage ?? 0.52) * 100)
    readonly property bool isCharging: Battery.isCharging || Battery.isPluggedIn
    readonly property real timeRemainingSec: Battery.isCharging
        ? (Battery.timeToFullEffective ?? Battery.timeToFull ?? 0)
        : (Battery.isPluggedIn ? 0 : (Battery.timeToEmpty ?? 0))
    readonly property int hoursRemaining: Math.floor(timeRemainingSec / 3600)
    readonly property string batteryStatus: {
        if (Battery.atChargeCeiling) {
            return Battery.chargeLimitReached
                ? Translation.tr("Charge limit reached")
                : Translation.tr("Fully charged");
        }
        if (root.hoursRemaining > 0)
            return "~ " + root.hoursRemaining + " " + Translation.tr("hours");
        if (Battery.isPluggedIn && !Battery.isCharging)
            return Translation.tr("Plugged in");
        return Translation.tr("Calculating...");
    }

    // Charging turns the card a fixed light green, so its bars and text take a
    // fixed dark green: a palette accent is light on a dark theme and vanished
    // against it.
    readonly property color lightGreenCharging: "#c4f3a6"
    readonly property color darkGreenOnCharging: "#1f3a10"

    readonly property color activeCardBg: root.isCharging ? root.lightGreenCharging : WidgetColorScheme.cardBgColor
    readonly property color activeAccentColor: root.isCharging ? root.darkGreenOnCharging : WidgetColorScheme.accentColor

    StyledRectangularShadow {
        id: bgShadow
        target: cardBg
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: cardBg
        anchors.fill: parent
        color: WidgetColorScheme.tintBackground(root.activeCardBg)
        radius: Appearance.rounding.windowRounding

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 0

            // Top Header: Charging Bolt + Percentage
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                MaterialSymbol {
                    visible: root.isCharging
                    text: "bolt"
                    iconSize: 26
                    color: root.activeAccentColor
                }

                Text {
                    visible: root.showPercentage
                    text: root.batteryPct + "%"
                    color: root.activeAccentColor
                    font {
                        pixelSize: 34
                        weight: Font.Normal
                        bold: false
                        family: "Google Sans Flex"
                        variableAxes: ({ "wght": 600, "ROND": 100 })
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Center 5 Vertical Bars Container
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 170
                Layout.preferredHeight: 76
                radius: 18
                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.12)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Repeater {
                        model: 5

                        delegate: Item {
                            id: barDelegate
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            readonly property int barIndex: index // 0 to 4
                            readonly property real barThreshold: (barIndex + 1) * 20.0
                            readonly property real prevThreshold: barIndex * 20.0
                            readonly property real currentPct: root.batteryPct

                            // Fill ratio for this specific bar (0.0 to 1.0)
                            readonly property real fillRatio: {
                                if (currentPct >= barThreshold) return 1.0
                                if (currentPct <= prevThreshold) return 0.0
                                return (currentPct - prevThreshold) / 20.0
                            }

                            // Background Track for Bar
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.15)
                            }

                            // Active Fill Bar (Decreasing height from top to bottom)
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: parent.height * barDelegate.fillRatio
                                radius: 8
                                color: root.activeAccentColor

                                Behavior on height {
                                    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            // Bottom Estimated Time Text
            Text {
                visible: root.showStatus
                Layout.alignment: Qt.AlignHCenter
                text: root.batteryStatus
                color: ColorUtils.applyAlpha(root.activeAccentColor, 0.70)
                font {
                    pixelSize: 17
                    weight: Font.Medium
                    family: "Google Sans Flex"
                }
            }
        }
    }
}
