pragma ComponentBehavior: Bound

import QtQuick
import stage.modules.common
import stage.modules.common.widgets
import stage.services

Item {
    id: root

    property string type: "battery" // "battery" | "weather_temp" | "none"
    property color textColor: WidgetColorScheme.textColorOnBg
    property color subtextColor: WidgetColorScheme.subtextColorOnBg
    property color accentColor: WidgetColorScheme.accentColor
    property color pillBg: WidgetColorScheme.pillBgColor

    implicitWidth: parent.width * 0.18
    implicitHeight: parent.width * 0.09

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.pillBg
        opacity: 0.85

        Row {
            anchors.centerIn: parent
            spacing: 3

            // Battery
            MaterialSymbol {
                visible: root.type === "battery"
                text: Battery.isCharging ? "battery_charging_full" : "battery_std"
                iconSize: Math.round(parent.parent.height * 0.55)
                color: root.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.type === "battery"
                text: Math.round(Battery.percentage * 100) + "%"
                color: WidgetColorScheme.textColorOnPillTrack
                font.pixelSize: parent.parent.height * 0.50
                font.weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }

            // Weather Temp
            MaterialSymbol {
                visible: root.type === "weather_temp"
                text: "device_thermostat"
                iconSize: Math.round(parent.parent.height * 0.55)
                color: root.accentColor
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                visible: root.type === "weather_temp"
                text: (Weather.data.temp || "--") + "°"
                color: WidgetColorScheme.textColorOnPillTrack
                font.pixelSize: parent.parent.height * 0.50
                font.weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
