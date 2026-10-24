import stage.services
import stage.modules.common
import stage.modules.common.widgets
import QtQuick

Item {
    id: root
    property bool isMonth: false
    property real targetSize: 0
    property alias text: bubbleText.text

    text: Qt.locale().toString(DateTime.clock.date, root.isMonth ? "MM" : "d")

    MaterialShape {
        id: bubble
        z: 5
        shape: root.isMonth ? MaterialShape.Shape.Pill : MaterialShape.Shape.Pentagon
        anchors.centerIn: parent
        color: root.isMonth ? WidgetColorScheme.pillBgColor : WidgetColorScheme.pillFillColor
        implicitSize: targetSize
    }

    StyledText {
        id: bubbleText
        z: 6
        anchors.centerIn: parent
        color: root.isMonth ? WidgetColorScheme.textColorOnPillTrack : WidgetColorScheme.textColorOnPillFill
        font {
            family: Appearance.font.family.expressive
            pixelSize: 30
            weight: Font.Black
        }
    }
}