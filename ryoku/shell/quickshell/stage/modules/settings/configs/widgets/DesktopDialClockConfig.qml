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
            text: Translation.tr("Dial Clock Options")
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
            visible: !Config.isWidgetActive("clock_dial")

            PagePlaceholder {
                anchors.fill: parent
                icon: "alarm_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Clock widget disabled")
                description: Translation.tr("Enable the Dial Clock widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_dial")

            // ── Hour Hand Style ──
            ContentSubsection {
                title: Translation.tr("Hour hand")
                icon: "arrow_upward"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_dial.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_dial.hourHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "horizontal_rule",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Fill"),
                            icon: "square",
                            value: "fill"
                        },
                        {
                            displayName: Translation.tr("Hollow"),
                            icon: "crop_square",
                            value: "hollow"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "do_not_disturb",
                            value: "hide"
                        }
                    ]
                }
            }

            // ── Minute Hand Style ──
            ContentSubsection {
                title: Translation.tr("Minute hand")
                icon: "arrow_downward"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_dial.minuteHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_dial.minuteHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Thin"),
                            icon: "horizontal_rule",
                            value: "thin"
                        },
                        {
                            displayName: Translation.tr("Medium"),
                            icon: "remove",
                            value: "medium"
                        },
                        {
                            displayName: Translation.tr("Bold"),
                            icon: "add",
                            value: "bold"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "format_list_bulleted",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "do_not_disturb",
                            value: "hide"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Second hand")
                icon: "timer"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_dial.secondHandStyle ?? "dot"
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_dial.secondHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Dot"),
                            icon: "circle",
                            value: "dot"
                        },
                        {
                            displayName: Translation.tr("Line"),
                            icon: "remove",
                            value: "line"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "format_list_bulleted",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "do_not_disturb",
                            value: "hide"
                        }
                    ]
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Other Hands ──
            ContentSubsectionLabel {
                text: Translation.tr("Other Hands")
            }

            ConfigSwitch {
                buttonIcon: "schedule"
                text: Translation.tr("Show Minute Hand")
                checked: Config.options.background.widgets.clock_dial.showMinuteHand ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showMinuteHand = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Show Second Hand")
                checked: Config.options.background.widgets.clock_dial.showSecondHand ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showSecondHand = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Dial Elements ──
            ContentSubsectionLabel {
                text: Translation.tr("Dial Elements")
            }

            ConfigSwitch {
                buttonIcon: "reorder"
                text: Translation.tr("Show Dial Ticks")
                checked: Config.options.background.widgets.clock_dial.showTicks ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showTicks = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "pin"
                text: Translation.tr("Show Number Ring (12, 3, 6, 9)")
                checked: Config.options.background.widgets.clock_dial.showNumberRing ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.showNumberRing = checked;
                }
            }

            Item { Layout.preferredHeight: 4 }

            // ── Visual Options ──
            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.clock_dial.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.enableShadows = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Inner Shadow")
                checked: Config.options.background.widgets.clock_dial.enableInnerShadow ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.clock_dial.enableInnerShadow = checked;
                }
            }
        }
    }
}
