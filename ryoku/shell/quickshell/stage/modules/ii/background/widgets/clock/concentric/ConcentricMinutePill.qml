pragma ComponentBehavior: Bound

import QtQuick
import stage.modules.common
import stage.modules.common.widgets
import stage.services

Item {
    id: root

    property int minute: DateTime.clock.minutes
    property string minuteStyle: "pill_horizontal" // "pill_horizontal" | "pill_round" | "text_only" | "capsule_extended" | "hide"
    property bool boldFont: false

    property color textColor: WidgetColorScheme.textColorOnBg
    property color outlineColor: WidgetColorScheme.subtextColorOnBg
    property color pillBg: WidgetColorScheme.pillBgColor
    property color accentColor: WidgetColorScheme.accentColor
    property real baseWidth: 240

    readonly property string minuteString: minute < 10 ? "0" + minute : "" + minute

    implicitWidth: mainShape.implicitWidth
    implicitHeight: mainShape.implicitHeight

    Rectangle {
        id: mainShape
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        implicitWidth: {
            if (root.minuteStyle === "pill_horizontal") return root.baseWidth * 0.52;
            if (root.minuteStyle === "pill_round") return root.baseWidth * 0.20;
            return minuteText.implicitWidth + 16;
        }

        implicitHeight: {
            if (root.minuteStyle === "pill_horizontal") return root.baseWidth * 0.18;
            if (root.minuteStyle === "pill_round") return root.baseWidth * 0.20;
            return minuteText.implicitHeight + 8;
        }

        radius: height / 2
        color: root.minuteStyle === "pill_round" ? root.pillBg : "transparent"
        border.color: root.minuteStyle === "pill_horizontal" ? root.outlineColor : "transparent"
        border.width: root.minuteStyle === "pill_horizontal" ? 1.5 : 0

        StyledText {
            id: minuteText
            anchors.left: parent.left
            anchors.leftMargin: root.minuteStyle === "pill_horizontal" ? parent.height * 0.35 : 0
            anchors.centerIn: (root.minuteStyle === "pill_round" || root.minuteStyle === "text_only") ? parent : undefined
            anchors.verticalCenter: parent.verticalCenter
            text: root.minuteString
            color: root.textColor
            font {
                family: root.boldFont ? Appearance.font.family.display : Appearance.font.family.title
                pixelSize: mainShape.height * 0.55
                weight: root.boldFont ? Font.Bold : Font.Normal
            }
        }
    }
}

