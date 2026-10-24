pragma ComponentBehavior: Bound

import stage.services
import stage.modules.common
import stage.modules.common.widgets
import QtQuick

Column {
    id: root
    property list<string> clockNumbers: DateTime.time.split(/[: ]/)
    property bool isEnabled: Config.options.background.widgets.clock_cookie.timeIndicators
    property color color: WidgetColorScheme.highlightCircleColor

    property bool hourMarksEnabled: Config.options.background.widgets.clock_cookie.hourMarks
    spacing: -16

    Repeater {
        model: root.clockNumbers

        delegate: StyledText {
            required property string modelData
            text: modelData.padStart(2, "0")
            property bool isAmPm: !text.match(/\d{2}/i)
            property real numberSizeWithoutGlow: isAmPm ? 26 : 68
            property real numberSizeWithGlow: isAmPm ? 20 : 40
            property real numberSize: root.hourMarksEnabled ? numberSizeWithGlow : numberSizeWithoutGlow

            anchors.horizontalCenter: root.horizontalCenter
            color: root.color
            font {
                family: Appearance.font.family.numbers
                weight: Font.Bold
                pixelSize: numberSize
                variableAxes: ({ "wght": 900 })
            }

            Behavior on numberSize {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
        }
    }
}
