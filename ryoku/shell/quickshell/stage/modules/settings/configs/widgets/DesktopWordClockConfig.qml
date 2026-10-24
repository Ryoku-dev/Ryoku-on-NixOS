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
            text: Translation.tr("Word Clock Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Word Clock Settings")
        icon: "schedule"

        Item {
            Layout.fillWidth: true
            implicitHeight: 180
            visible: !Config.isWidgetActive("clock_word")
            PagePlaceholder {
                anchors.fill: parent
                icon: "schedule"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Word Clock disabled")
                description: Translation.tr("Enable the Word Clock in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("clock_word")

            ContentSubsectionLabel { text: Translation.tr("Widget Size") }

            ConfigSlider {
                buttonIcon: "format_size"
                text: Translation.tr("Size")
                from: 160
                to: 420
                stepSize: 10
                value: Config.options.background.widgets.clock_word.size
                onValueChanged: {
                    Config.options.background.widgets.clock_word.size = Math.round(value);
                }
            }
            ContentSubsection {
                title: Translation.tr("Background style")
                icon: "wallpaper"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_word.backgroundStyle ?? "shape"
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_word.backgroundStyle = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Transparent"), icon: "visibility_off", value: "transparent" },
                        { displayName: Translation.tr("Shape"), icon: "category", value: "shape" }
                    ]
                }
            }

            ContentSubsection {
                visible: (Config.options.background.widgets.clock_word.backgroundStyle ?? "shape") === "shape"
                title: Translation.tr("Background shape")
                icon: "category"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock_word.backgroundShape ?? "Circle"
                    onSelected: newValue => {
                        Config.options.background.widgets.clock_word.backgroundShape = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Circle"), icon: "circle", value: "Circle" },
                        { displayName: Translation.tr("Square"), icon: "square", value: "Square" },
                        { displayName: Translation.tr("Cookie"), icon: "cookie", value: "Cookie12Sided" }
                    ]
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.enableShadows ?? false
                onCheckedChanged: {
                    Config.options.background.widgets.enableShadows = checked;
                }
            }
        }
    }
}
