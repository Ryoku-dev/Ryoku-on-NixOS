import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
ContentPage {
    id: root
    forceWidth: false

    signal goBack()

    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("WearOS Arc Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Arc Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("wearos_arc_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("WearOS Arc Clock disabled")
                description: Translation.tr("Enable the WearOS Arc Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("wearos_arc_clock")

            // ── Size ──
            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.wearos_arc_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.wearos_arc_clock.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 8 }

            // ── Appearance Toggles ──
            ContentSubsectionLabel {
                text: Translation.tr("Appearance")
            }

            ConfigSwitch {
                buttonIcon: "dark_mode"
                text: Translation.tr("AMOLED Black Background")
                checked: Config.options.background.widgets.wearos_arc_clock.blackBackground ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.blackBackground = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "lens"
                text: Translation.tr("Enable Glass Reflection")
                checked: Config.options.background.widgets.wearos_arc_clock.enableGlassReflection ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.enableGlassReflection = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "grid_on"
                text: Translation.tr("Enable Background Dotted Pattern")
                checked: Config.options.background.widgets.wearos_arc_clock.enableBackgroundPattern ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.enableBackgroundPattern = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "content_copy"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.wearos_arc_clock.enableShadows ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_arc_clock.enableShadows = checked;
                }
            }

            Item { Layout.preferredHeight: 8 }

            // ── Complications ──
            ContentSubsectionLabel {
                text: Translation.tr("Complications")
            }

            // Left Complication selection
            ContentSubsection {
                title: Translation.tr("Left Complication")
                icon: "west"
                Layout.fillWidth: true

                StyledComboBox {
                    buttonIcon: "star"
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Weather Info"), value: "weather" },
                        { displayName: Translation.tr("Laptop Battery"), value: "battery" },
                        { displayName: Translation.tr("KdeConnect Phone Battery"), value: "phone_battery" },
                        { displayName: Translation.tr("Bluetooth Battery"), value: "bluetooth_battery" },
                        { displayName: Translation.tr("Water Drink Counter"), value: "water_reminder" },
                        { displayName: Translation.tr("CPU Usage"), value: "cpu_usage" },
                        { displayName: Translation.tr("RAM Memory Usage"), value: "memory_usage" },
                        { displayName: Translation.tr("None"), value: "none" }
                    ]
                    currentIndex: {
                        const activeVal = Config.options.background.widgets.wearos_arc_clock.leftComplication ?? "weather";
                        const idx = model.findIndex(item => item.value === activeVal);
                        return idx !== -1 ? idx : 0;
                    }
                    onActivated: index => {
                        Config.options.background.widgets.wearos_arc_clock.leftComplication = model[index].value;
                    }
                }
            }

            // Right Complication selection
            ContentSubsection {
                title: Translation.tr("Right Complication")
                icon: "east"
                Layout.fillWidth: true

                StyledComboBox {
                    buttonIcon: "star"
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Weather Info"), value: "weather" },
                        { displayName: Translation.tr("Laptop Battery"), value: "battery" },
                        { displayName: Translation.tr("KdeConnect Phone Battery"), value: "phone_battery" },
                        { displayName: Translation.tr("Bluetooth Battery"), value: "bluetooth_battery" },
                        { displayName: Translation.tr("Water Drink Counter"), value: "water_reminder" },
                        { displayName: Translation.tr("CPU Usage"), value: "cpu_usage" },
                        { displayName: Translation.tr("RAM Memory Usage"), value: "memory_usage" },
                        { displayName: Translation.tr("None"), value: "none" }
                    ]
                    currentIndex: {
                        const activeVal = Config.options.background.widgets.wearos_arc_clock.rightComplication ?? "battery";
                        const idx = model.findIndex(item => item.value === activeVal);
                        return idx !== -1 ? idx : 0;
                    }
                    onActivated: index => {
                        Config.options.background.widgets.wearos_arc_clock.rightComplication = model[index].value;
                    }
                }
            }

            // Bottom Complication selection
            ContentSubsection {
                title: Translation.tr("Bottom Complication")
                icon: "south"
                Layout.fillWidth: true

                StyledComboBox {
                    buttonIcon: "title"
                    textRole: "displayName"
                    model: [
                        { displayName: Translation.tr("Calendar Next Event"), value: "calendar" },
                        { displayName: Translation.tr("Tasks"), value: "todo" },
                        { displayName: Translation.tr("Active Media Status"), value: "media" },
                        { displayName: Translation.tr("Water Reminder Goal"), value: "water" },
                        { displayName: Translation.tr("None"), value: "none" }
                    ]
                    currentIndex: {
                        const activeVal = Config.options.background.widgets.wearos_arc_clock.bottomComplication ?? "calendar";
                        const idx = model.findIndex(item => item.value === activeVal);
                        return idx !== -1 ? idx : 0;
                    }
                    onActivated: index => {
                        Config.options.background.widgets.wearos_arc_clock.bottomComplication = model[index].value;
                    }
                }
            }
        }
    }
}
