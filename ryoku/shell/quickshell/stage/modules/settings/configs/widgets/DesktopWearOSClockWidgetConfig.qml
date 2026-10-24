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
            text: Translation.tr("WearOS Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("clock_wearos")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("WearOS Clock disabled")
                description: Translation.tr("Enable the WearOS Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_wearos")

            // ── Size ──
            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.wearos_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.wearos_clock.widgetSize = value;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Hands ──
            ContentSubsectionLabel {
                text: Translation.tr("Clock Hands")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show Minute Hand")
                checked: Config.options.background.widgets.wearos_clock.showMinuteHand ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showMinuteHand = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Dial Ring ──
            ContentSubsectionLabel {
                text: Translation.tr("Dial Ring")
            }

            ConfigSwitch {
                buttonIcon: "circle"
                text: Translation.tr("Show Bezel Ring")
                checked: Config.options.background.widgets.wearos_clock.showBezelRing ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showBezelRing = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pin"
                text: Translation.tr("Show Outer Numbers (00-58)")
                checked: Config.options.background.widgets.wearos_clock.showOuterNumbers ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showOuterNumbers = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "tag"
                text: Translation.tr("Show Inner Numbers (05-55)")
                checked: Config.options.background.widgets.wearos_clock.showInnerNumbers ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showInnerNumbers = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Complications ──
            ContentSubsectionLabel {
                text: Translation.tr("Complications")
            }

            ConfigSwitch {
                buttonIcon: "android"
                text: Translation.tr("Show Distro Logo")
                checked: Config.options.background.widgets.wearos_clock.showDistroLogo ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showDistroLogo = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Show Sunset Gauge")
                checked: Config.options.background.widgets.wearos_clock.showSunsetComplication ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showSunsetComplication = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show Digital Time Pill")
                checked: Config.options.background.widgets.wearos_clock.showDigitalTimePill ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showDigitalTimePill = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "battery_full"
                text: Translation.tr("Show Battery Pill")
                checked: Config.options.background.widgets.wearos_clock.showBatteryPill ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showBatteryPill = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "hourglass_bottom"
                text: Translation.tr("Show Hour Sub-Dial")
                checked: Config.options.background.widgets.wearos_clock.showHourSubDial ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showHourSubDial = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "bedtime"
                text: Translation.tr("Show Bedtime Icon")
                checked: Config.options.background.widgets.wearos_clock.showBedtimeIcon ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showBedtimeIcon = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "phone_android"
                text: Translation.tr("Show KDE Connect Status")
                checked: Config.options.background.widgets.wearos_clock.showKdeConnect ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showKdeConnect = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "calendar_today"
                text: Translation.tr("Show Date Complication")
                checked: Config.options.background.widgets.wearos_clock.showDateComplication ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.showDateComplication = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Visual Options ──
            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Glass Reflection")
                checked: Config.options.background.widgets.wearos_clock.enableGlassReflection ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.enableGlassReflection = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.wearos_clock.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.wearos_clock.enableShadows = checked;
                }
            }
        }
    }
}
