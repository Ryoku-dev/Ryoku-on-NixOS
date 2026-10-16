import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.settings.configs.widgets

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
            text: Translation.tr("Forecast Weather 2x1 Options")
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
            visible: !Config.isWidgetActive("weather_forecast")

            PagePlaceholder {
                anchors.fill: parent
                icon: "cloud_off"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Forecast Weather widget disabled")
                description: Translation.tr("Enable the Forecast Weather 2x1 widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("weather_forecast")

            DesktopWeatherBehaviorOptions {
                options: Config.options.background.widgets.weather_forecast
                expressiveColors: true
                location: true
                forecast: true
                refresh: true
            }

            // Visual Options
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                DesktopWeatherShadowOptions {
                    Layout.fillWidth: true
                }
            }
        }
    }
}
