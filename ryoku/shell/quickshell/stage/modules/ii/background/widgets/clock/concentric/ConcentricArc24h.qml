pragma ComponentBehavior: Bound

import QtQuick
import stage.modules.common
import stage.modules.common.functions
import stage.modules.common.widgets
import stage.services

Item {
    id: root

    property color textColor: WidgetColorScheme.textColorOnBg
    property color subtextColor: WidgetColorScheme.subtextColorOnBg
    property color accentColor: WidgetColorScheme.accentColor

    property int hour: DateTime.clock.hours
    property int minute: DateTime.clock.minutes
    readonly property real progress: (hour * 60 + minute) / 1440.0

    anchors.fill: parent

    Canvas {
        id: arcCanvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();

            var cx = width / 2;
            var cy = height / 2;
            var r = width * 0.43;

            var startAngle = Math.PI * 1.15; // ~207 deg
            var endAngle = Math.PI * 1.85;   // ~333 deg

            // Track
            ctx.beginPath();
            ctx.arc(cx, cy, r, startAngle, endAngle);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = ColorUtils.applyAlpha(root.subtextColor, 0.25);
            ctx.stroke();

            // Active Arc
            var currentAngle = startAngle + (endAngle - startAngle) * root.progress;
            ctx.beginPath();
            ctx.arc(cx, cy, r, startAngle, currentAngle);
            ctx.lineWidth = 2.5;
            ctx.strokeStyle = root.accentColor;
            ctx.stroke();
        }

        Connections {
            target: DateTime.clock
            function onMinutesChanged() { arcCanvas.requestPaint(); }
        }
    }

    StyledText {
        text: "≈24"
        color: root.subtextColor
        font.pixelSize: parent.width * 0.035
        font.weight: Font.DemiBold
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.04
    }
}
