import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
ContentPage {
    id: root
    forceWidth: false

    signal goBack

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
            text: Translation.tr("Concentric Clock Options")
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
            visible: !Config.isWidgetActive("concentric_clock")

            PagePlaceholder {
                anchors.fill: parent
                icon: "watch"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Concentric Clock disabled")
                description: Translation.tr("Enable the Concentric Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("concentric_clock")

            // ── Size ──
            ContentSubsectionLabel {
                text: Translation.tr("Size")
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text: Translation.tr("Widget Size")
                value: Config.options.background.widgets.concentric_clock.widgetSize ?? 100
                from: 50
                to: 200
                stepSize: 10
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.widgetSize = value;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Dial Style ──
            ContentSubsection {
                title: Translation.tr("Dial style")
                icon: "timelapse"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.dialStyle ?? "concentric"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.dialStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Concentric"),
                            icon: "timelapse",
                            value: "concentric"
                        },
                        {
                            displayName: Translation.tr("Outer Only"),
                            icon: "panorama_fish_eye",
                            value: "outer_only"
                        },
                        {
                            displayName: Translation.tr("Inner Only"),
                            icon: "adjust",
                            value: "inner_only"
                        },
                        {
                            displayName: Translation.tr("Pixel Watch 3 Dial"),
                            icon: "watch",
                            value: "full_pixel3"
                        },
                        {
                            displayName: Translation.tr("Full Dense"),
                            icon: "grid_on",
                            value: "full_dense"
                        },
                        {
                            displayName: Translation.tr("Minimal Arc"),
                            icon: "donut_large",
                            value: "minimal_arc"
                        },
                        {
                            displayName: Translation.tr("Dots"),
                            icon: "more_horiz",
                            value: "dots"
                        },
                        {
                            displayName: Translation.tr("Numbers (3-6-9-12)"),
                            icon: "format_list_numbered",
                            value: "numbers"
                        },
                        {
                            displayName: Translation.tr("Full Ticks"),
                            icon: "graphic_eq",
                            value: "full"
                        },
                        {
                            displayName: Translation.tr("Material Shapes"),
                            icon: "category",
                            value: "shapes"
                        },
                        {
                            displayName: Translation.tr("None"),
                            icon: "visibility_off",
                            value: "none"
                        }
                    ]
                }
            }

            // ── Frame Style ──
            ContentSubsection {
                title: Translation.tr("Frame style")
                icon: "panorama_fish_eye"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.frameStyle ?? "none"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.frameStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("None"),
                            icon: "do_not_disturb",
                            value: "none"
                        },
                        {
                            displayName: Translation.tr("Thin Ring"),
                            icon: "radio_button_unchecked",
                            value: "ring_thin"
                        },
                        {
                            displayName: Translation.tr("Thick Ring"),
                            icon: "circle",
                            value: "ring_thick"
                        },
                        {
                            displayName: Translation.tr("Dot Ring"),
                            icon: "more_horiz",
                            value: "dot_ring"
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "format_bold"
                text: Translation.tr("Bold Typography")
                checked: Config.options.background.widgets.concentric_clock.boldFont ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.boldFont = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "title"
                text: Translation.tr("Show Hour Text")
                checked: Config.options.background.widgets.concentric_clock.showHourText ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.showHourText = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "more_time"
                text: Translation.tr("24-Hour Format")
                checked: Config.options.background.widgets.concentric_clock.use24h ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.use24h = checked;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Hands & Marks ──
            ContentSubsectionLabel {
                text: Translation.tr("Analog Hands & Marks")
            }

            ContentSubsection {
                title: Translation.tr("Hour hand style")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.hourHandStyle ?? "hide"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.hourHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Fill"),
                            icon: "crop_square",
                            value: "fill"
                        },
                        {
                            displayName: Translation.tr("Hollow"),
                            icon: "crop_square",
                            value: "hollow"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "format_list_bulleted",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "visibility_off",
                            value: "hide"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Minute hand style")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.minuteHandStyle ?? "hide"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.minuteHandStyle = newValue;
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
                            icon: "visibility_off",
                            value: "hide"
                        }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Second hand style")
                icon: "timer"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.secondHandStyle ?? "hide"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.secondHandStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Dot"),
                            icon: "fiber_manual_record",
                            value: "dot"
                        },
                        {
                            displayName: Translation.tr("Line"),
                            icon: "horizontal_rule",
                            value: "line"
                        },
                        {
                            displayName: Translation.tr("Classic"),
                            icon: "format_list_bulleted",
                            value: "classic"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "visibility_off",
                            value: "hide"
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "grid_on"
                text: Translation.tr("Show Inner Hour Marks")
                checked: Config.options.background.widgets.concentric_clock.showHourMarks ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.showHourMarks = checked;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Minute Complication ──
            ContentSubsectionLabel {
                text: Translation.tr("Minute Pill Complication")
            }

            ContentSubsection {
                title: Translation.tr("Minute pill style")
                icon: "schedule"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.minuteStyle ?? "pill_horizontal"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.minuteStyle = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Horizontal"),
                            icon: "crop_7_5",
                            value: "pill_horizontal"
                        },
                        {
                            displayName: Translation.tr("Round"),
                            icon: "circle",
                            value: "pill_round"
                        },
                        {
                            displayName: Translation.tr("Text Only"),
                            icon: "title",
                            value: "text_only"
                        },
                        {
                            displayName: Translation.tr("Hide"),
                            icon: "visibility_off",
                            value: "hide"
                        }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "fiber_manual_record"
                text: Translation.tr("Show Minute Dot on Ring")
                checked: Config.options.background.widgets.concentric_clock.showMinuteDot ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.showMinuteDot = checked;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Sub-Dials & Arcs ──
            ContentSubsectionLabel {
                text: Translation.tr("Sub-Dials & Arcs")
            }

            ConfigSwitch {
                buttonIcon: "rotate_right"
                text: Translation.tr("Show 24h Progress Arc")
                checked: Config.options.background.widgets.concentric_clock.showArc24h ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.showArc24h = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "watch"
                text: Translation.tr("Show Hour Sub-Dial (7:30)")
                checked: Config.options.background.widgets.concentric_clock.showHourSubDial ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.showHourSubDial = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Show Sunset Sub-Dial (Top)")
                checked: Config.options.background.widgets.concentric_clock.showSunsetDial ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.showSunsetDial = checked;
                }
            }

            ContentSubsection {
                title: Translation.tr("Bottom complication")
                icon: "widgets"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.concentric_clock.bottomSubDialContent ?? "battery"
                    onSelected: newValue => {
                        Config.options.background.widgets.concentric_clock.bottomSubDialContent = newValue;
                    }
                    options: [
                        {
                            displayName: Translation.tr("Battery"),
                            icon: "battery_full",
                            value: "battery"
                        },
                        {
                            displayName: Translation.tr("Weather"),
                            icon: "device_thermostat",
                            value: "weather_temp"
                        },
                        {
                            displayName: Translation.tr("None"),
                            icon: "visibility_off",
                            value: "none"
                        }
                    ]
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Positioning & Offsets ──
            ContentSubsectionLabel {
                text: Translation.tr("Positioning & Offsets")
            }

            ConfigSlider {
                buttonIcon: "horizontal_distribute"
                text: Translation.tr("Minute Pill Position X (%)")
                value: Config.options.background.widgets.concentric_clock.minutePillLeftMargin ?? 58
                from: 20
                to: 90
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.minutePillLeftMargin = value;
                }
            }

            ConfigSlider {
                buttonIcon: "open_in_full"
                text: Translation.tr("Sub-Dials Margin Offset (%)")
                value: Config.options.background.widgets.concentric_clock.subdialMarginOffset ?? 0
                from: -10
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.subdialMarginOffset = value;
                }
            }

            ConfigSlider {
                buttonIcon: "adjust"
                text: Translation.tr("Dial Rings Margin Offset (%)")
                value: Config.options.background.widgets.concentric_clock.dialMarginOffset ?? 0
                from: -10
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.dialMarginOffset = value;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Hour Text Styling ──
            ContentSubsectionLabel {
                text: Translation.tr("Hour Text Dimensions & Font")
            }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Hour Font Size (% of base)")
                value: Config.options.background.widgets.concentric_clock.hourPixelSize ?? 36
                from: 10
                to: 80
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.hourPixelSize = value;
                }
            }

            ConfigSlider {
                buttonIcon: "line_weight"
                text: Translation.tr("Hour Font Weight")
                value: Config.options.background.widgets.concentric_clock.hourFontWeight ?? 700
                from: 100
                to: 900
                stepSize: 100
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.hourFontWeight = value;
                }
            }

            ConfigSlider {
                buttonIcon: "swap_horiz"
                text: Translation.tr("Hour Font Variable Width (wdth)")
                value: Config.options.background.widgets.concentric_clock.hourFontWidth ?? 100
                from: 50
                to: 150
                stepSize: 5
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.hourFontWidth = value;
                }
            }

            ConfigSlider {
                buttonIcon: "rounded_corner"
                text: Translation.tr("Hour Font Variable Roundness (ROND)")
                value: Config.options.background.widgets.concentric_clock.hourFontRound ?? 0
                from: 0
                to: 100
                stepSize: 5
                onValueChanged: {
                    Config.options.background.widgets.concentric_clock.hourFontRound = value;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Quote Settings ──
            ContentSubsectionLabel {
                text: Translation.tr("Quote Settings")
            }

            ConfigSwitch {
                buttonIcon: "format_quote"
                text: Translation.tr("Enable Bottom Quote")
                checked: Config.options.background.widgets.concentric_clock.quoteEnable ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.quoteEnable = checked;
                }
            }

            ConfigTextField {
                enabled: Config.options.background.widgets.concentric_clock.quoteEnable ?? false
                icon: "edit"
                text: Translation.tr("Quote text")
                inputText: Config.options.background.widgets.concentric_clock.quoteText ?? ""
                onInputTextChanged: {
                    Config.options.background.widgets.concentric_clock.quoteText = inputText;
                }
            }

            Item {
                Layout.preferredHeight: 4
            }

            // ── Visual Options ──
            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSwitch {
                buttonIcon: "contrast"
                text: Translation.tr("Use Black Background (WearOS style)")
                checked: Config.options.background.widgets.concentric_clock.useBlackBg ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.useBlackBg = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable Glass Reflection")
                checked: Config.options.background.widgets.concentric_clock.enableGlassReflection ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.enableGlassReflection = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.concentric_clock.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.concentric_clock.enableShadows = checked;
                }
            }
        }
    }
}
