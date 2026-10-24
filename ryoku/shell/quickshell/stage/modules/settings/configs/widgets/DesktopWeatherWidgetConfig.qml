import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.settings.configs.widgets

ContentPage {
    id: root
    forceWidth: false
    property string widget: ""
    readonly property bool isExpressive: widget === "iiWeatherExpressive"
        || widget === "weather_expressive"
    readonly property string targetWidgetId: isExpressive
        ? "weather_expressive" : "weather_default"
    readonly property var weatherOptions: Config.options.background.widgets.weather

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
            text: Translation.tr("Weather Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Weather Settings")
        icon: "cloud"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive(root.targetWidgetId)

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Weather widget disabled")
                description: Translation.tr("Enable this weather widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive(root.targetWidgetId)

            ContentSubsection {
                visible: root.isExpressive
                title: Translation.tr("Background shape")
                icon: "category"
                Layout.fillWidth: true

                ConfigSelectionArray {
                    currentValue: root.weatherOptions.backgroundShape ?? "Cookie9Sided"
                    onSelected: newValue => {
                        root.weatherOptions.backgroundShape = newValue;
                    }
                    options: ["Circle", "Pill", "Oval", "SemiCircle", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided", "Ghostish", "Puffy", "PuffyDiamond", "Bun", "SoftBurst", "Sunny", "VerySunny"].map(icon => {
                        return {
                            displayName: "",
                            shape: icon,
                            value: icon
                        };
                    })
                }
            }
            DesktopWeatherBehaviorOptions {
                options: root.weatherOptions
                expressiveColors: true
                temperature: true
                icon: !root.isExpressive
            }

            // Visual Options (Shadows)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                DesktopWeatherShadowOptions {
                    innerShadow: true
                    Layout.fillWidth: true
                }
            }
        }
    }
}
