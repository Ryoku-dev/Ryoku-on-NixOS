pragma ComponentBehavior: Bound

import QtQuick
import stage.modules.common
import stage.modules.common.widgets
import stage.services

Item {
    id: root

    property string type: "hour" // "hour" | "sunset"
    property color textColor: WidgetColorScheme.textColorOnBg
    property color subtextColor: WidgetColorScheme.subtextColorOnBg
    property color accentColor: WidgetColorScheme.accentColor

    property int hour: DateTime.clock.hours
    property int minute: DateTime.clock.minutes

    readonly property real hourRotation: ((hour % 12) * 30) + (minute * 0.5)

    implicitWidth: parent.width * 0.22
    implicitHeight: implicitWidth

    // ── TYPE 1: HOUR SUB-DIAL ──
    Item {
        anchors.fill: parent
        visible: root.type === "hour"

        // Current hour text
        StyledText {
            text: root.hour % 12 === 0 ? 12 : root.hour % 12
            color: root.textColor
            font.pixelSize: parent.height * 0.32
            font.weight: Font.Bold
            anchors.centerIn: parent
        }
    }

    // ── TYPE 2: SUNSET SUB-DIAL ──
    Item {
        anchors.fill: parent
        visible: root.type === "sunset"

        readonly property string sunsetTime: Weather.data.sunset || "18:00"

        Row {
            anchors.centerIn: parent
            spacing: 3

            MaterialSymbol {
                text: "sunny"
                fill: 1
                iconSize: Math.round(root.height * 0.35)
                color: root.textColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                text: parent.parent.sunsetTime
                color: root.textColor
                font.pixelSize: root.height * 0.32
                font.weight: Font.Bold
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
