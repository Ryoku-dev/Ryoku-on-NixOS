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

    configEntryName: "weather_icon"

    readonly property var options: Config.options.background.widgets.weather_icon
    readonly property string shapeString: options.backgroundShape ?? "Cookie12Sided"
    readonly property string colorScheme: (options.expressiveColors ?? true)
        ? "expressive_primary" : "default"

    implicitWidth: 240
    implicitHeight: 240

    readonly property color cardBgColor: WidgetColorScheme.getCardBgColor(colorScheme)

    StyledDropShadow {
        id: shadowEffect
        target: weatherShape
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    MaterialShape {
        id: weatherShape
        anchors.centerIn: parent
        implicitSize: Math.min(root.width, root.height)
        shapeString: root.shapeString
        color: "transparent"

        MaterialShape {
            id: bgShape
            anchors.fill: parent
            shapeString: parent.shapeString
            color: WidgetColorScheme.tintBackground(root.cardBgColor)
            visible: (root.options.showBackground ?? true)
                && !(Config.options.background.widgets.enableInnerShadow ?? true)
        }

        InnerShadow {
            id: innerShadow
            anchors.fill: parent
            radius: 24
            samples: 49
            color: Qt.rgba(0, 0, 0, 0.35)
            source: bgShape
            visible: (root.options.showBackground ?? true)
                && (Config.options.background.widgets.enableInnerShadow ?? true)
        }

        Image {
            anchors.centerIn: parent
            source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
            sourceSize: Qt.size(110, 110)
        }
    }
}
