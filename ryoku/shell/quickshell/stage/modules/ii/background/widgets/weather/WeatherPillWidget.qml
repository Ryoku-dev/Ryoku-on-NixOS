import QtQuick
import QtQuick.Layouts
import stage
import stage.services
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
AbstractBackgroundWidget {
    id: root

    configEntryName: "weather_pill"

    implicitWidth: 240
    implicitHeight: 120

    readonly property var options: Config.options.background.widgets.weather_pill
    readonly property string colorScheme: (options.expressiveColors ?? true)
        ? "expressive_primary" : "default"
    readonly property color cardBgColor: WidgetColorScheme.getCardBgColor(colorScheme)
    readonly property color textColorOnBg: WidgetColorScheme.getTextColorOnBg(colorScheme)

    StyledDropShadow {
        id: shadowEffect
        target: mainContainer
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: mainContainer
        anchors.fill: parent
        radius: Appearance.rounding.full
        color: WidgetColorScheme.tintBackground(root.cardBgColor)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 18
            anchors.rightMargin: 36
            spacing: 8

            Image {
                visible: root.options.showIcon ?? true
                Layout.alignment: Qt.AlignVCenter
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(78, 78)
            }

            Item { Layout.fillWidth: true }

            StyledText {
                visible: root.options.showTemperature ?? true
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                text: Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : ""
                color: root.textColorOnBg
                font.pixelSize: Appearance.font.pixelSize.huge * 1.9
                font.weight: Font.Bold
            }
        }
    }
}
