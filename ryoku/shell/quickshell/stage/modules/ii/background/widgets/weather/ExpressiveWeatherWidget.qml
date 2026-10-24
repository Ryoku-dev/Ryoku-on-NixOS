import QtQuick
import QtQuick.Layouts
import stage
import stage.services
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
import Qt5Compat.GraphicalEffects

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather"

    readonly property var options: Config.options.background.widgets.weather
    readonly property string colorScheme: (options.expressiveColors ?? false)
        ? "expressive_primary" : "default"
    readonly property string tempText: Weather.data?.temp ?? "20°C"
    readonly property color cardBgColor: WidgetColorScheme.getCardBgColor(colorScheme)
    readonly property color tempBgColor: WidgetColorScheme.getInnerShapeColor(colorScheme)
    readonly property color textColor: WidgetColorScheme.getTextColorOnBg(colorScheme)

    implicitWidth: 200
    implicitHeight: 240

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        Item {
            Layout.preferredWidth: 200
            Layout.preferredHeight: 200
            Layout.alignment: Qt.AlignHCenter

            StyledDropShadow {
                id: weatherShadow
                target: weatherIconShape
                visible: Config.options.background.widgets.enableShadows ?? true
            }

            MaterialShape {
                id: weatherIconShape
                anchors.fill: parent
                shapeString: root.options.backgroundShape ?? "Cookie9Sided"
                color: "transparent"

                // Background shape matching main shape to serve as source for InnerShadow
                MaterialShape {
                    id: bgShape
                    anchors.fill: parent
                    shapeString: parent.shapeString
                    color: WidgetColorScheme.tintBackground(root.cardBgColor)
                    visible: !(Config.options.background.widgets.enableInnerShadow ?? true)
                }

                InnerShadow {
                    id: innerShadow
                    anchors.fill: parent
                    radius: 24 // balanced radius for expressive shape
                    samples: 49
                    color: Qt.rgba(0, 0, 0, 0.35) // deep soft shadow
                    source: bgShape
                    visible: Config.options.background.widgets.enableInnerShadow ?? true
                }

                Image {
                    anchors.centerIn: parent
                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                    sourceSize: Qt.size(120, 120)
                }
            }
        }

        Rectangle {
            visible: root.options.showTemperature ?? true
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 48 : 0
            Layout.alignment: Qt.AlignHCenter
            color: WidgetColorScheme.tintBackground(root.tempBgColor)
            radius: Appearance.rounding.small

            StyledText {
                anchors.centerIn: parent
                text: root.tempText
                color: root.textColor
                font.pixelSize: 42
                font.weight: Font.Bold
            }
        }
    }
}
