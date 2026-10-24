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

    configEntryName: "weather"

    readonly property var options: Config.options.background.widgets.weather
    readonly property string colorScheme: (options.expressiveColors ?? false)
        ? "expressive_primary" : "default"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.getCardBgColor(colorScheme)
    readonly property color accentColor: WidgetColorScheme.getAccentColor(colorScheme)

    StyledDropShadow {
        id: shadowEffect
        target: mainShape
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    MaterialShape {
        id: mainShape
        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height)
        shape: MaterialShape.Shape.Pill
        color: "transparent"

        MaterialShape {
            id: bgShape
            anchors.fill: parent
            shape: parent.shape
            color: WidgetColorScheme.tintBackground(root.cardBgColor)
            visible: !(Config.options.background.widgets.enableInnerShadow ?? true)
        }

        InnerShadow {
            id: innerShadow
            anchors.fill: parent
            radius: 24
            samples: 49
            color: Qt.rgba(0, 0, 0, 0.35)
            source: bgShape
            visible: Config.options.background.widgets.enableInnerShadow ?? true
        }

        Item {
            anchors.fill: parent

            StyledText {
                visible: root.options.showTemperature ?? true
                font.pixelSize: 88
                font.family: Appearance.font.family.main
                font.weight: Font.Black
                color: root.accentColor
                text: Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : ""
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 28
                anchors.topMargin: 36
                z: 1
            }

            Image {
                visible: root.options.showIcon ?? true
                source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                sourceSize: Qt.size(130, 130)
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 18
                anchors.bottomMargin: 18
                z: 2
            }
        }
    }
}
