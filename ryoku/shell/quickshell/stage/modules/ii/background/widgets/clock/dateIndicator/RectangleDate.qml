
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import QtQuick

Rectangle {
    id: rect
    readonly property string dialStyle: Config.options.background.widgets.clock_cookie.dialNumberStyle

    StyledText {
        anchors.centerIn: parent
        color: WidgetColorScheme.accentColor
        text: Qt.locale().toString(DateTime.clock.date, "dd")
        font {
            family: Appearance.font.family.expressive
            pixelSize: 20
            weight: 1000
        }
    }
}
