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

    configEntryName: "weather_circle"

    implicitWidth: 240
    implicitHeight: 240

    readonly property var options: Config.options.background.widgets.weather_circle
    readonly property string colorScheme: (options.expressiveColors ?? true)
        ? "expressive_primary" : "default"
    readonly property color outerCircleColor: WidgetColorScheme.getPillBgColor(colorScheme)
    readonly property color cookieBgColor: WidgetColorScheme.getCardBgColor(colorScheme)
    readonly property color textColorOnCookie: WidgetColorScheme.getTextColorOnBg(colorScheme)

    StyledDropShadow {
        id: shadowEffect
        target: outerCircle
        visible: Config.options.background.widgets.enableShadows ?? true
    }

    Rectangle {
        id: outerCircle
        anchors.centerIn: parent
        width: Math.min(root.width, root.height)
        height: width
        radius: width / 2
        color: WidgetColorScheme.tintBackground(root.outerCircleColor)

        MaterialShape {
            id: innerCookie
            anchors.centerIn: parent
            implicitSize: outerCircle.width * 0.90
            shapeString: "Cookie12Sided"
            color: "transparent"

            MaterialShape {
                id: cookieBg
                anchors.fill: parent
                shapeString: parent.shapeString
                color: WidgetColorScheme.tintBackground(root.cookieBgColor)
                visible: !(Config.options.background.widgets.enableInnerShadow ?? true)
            }

            InnerShadow {
                id: innerShadow
                anchors.fill: parent
                radius: 20
                samples: 41
                color: Qt.rgba(0, 0, 0, 0.40)
                source: cookieBg
                visible: Config.options.background.widgets.enableInnerShadow ?? true
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -6

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    source: WeatherIcons.getWeatherIcon(Weather.data?.wCode ?? 113, false)
                    sourceSize: Qt.size(96, 96)
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 4

                    StyledText {
                        visible: root.options.showTemperature ?? true
                        text: Weather.data?.temp ? Weather.data.temp.replace("°C", "°").replace("°F", "°") : ""
                        color: root.textColorOnCookie
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                    }

                    StyledText {
                        visible: root.options.showLocation ?? true
                        text: Weather.data?.city || ""
                        color: root.textColorOnCookie
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        Layout.maximumWidth: 100
                    }
                }
            }
        }
    }
}
