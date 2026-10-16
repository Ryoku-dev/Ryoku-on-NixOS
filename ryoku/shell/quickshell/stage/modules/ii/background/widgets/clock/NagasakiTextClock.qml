pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.background.widgets
AbstractBackgroundWidget {
    id: root

    configEntryName: "nagasaki_text"

    readonly property real configSize: Config.options.background.widgets.nagasaki_text.size ?? 200
    // The square fits the condensed Nagasaki digits; any other face is wider,
    // and the box grows with it so the widget's frame covers what it draws.
    implicitWidth: Math.max(configSize, Math.ceil(timeLabel.implicitWidth))
    implicitHeight: configSize

    FontLoader {
        id: nagasakiFont
        source: "file://" + Directories.assetsPath + "/fonts/nagasaki.ttf"
    }

    readonly property string hour: DateTime.time.split(":")[0].padStart(2, "0")
    readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
    readonly property string timeText: hour + minute

    readonly property string colorStyle: Config.options.background.widgets.nagasaki_text.colorStyle ?? "surface"
    readonly property color textColor: colorStyle === "accent"
        ? WidgetColorScheme.accentColor
        : colorStyle === "text" ? WidgetColorScheme.textColorOnBg : WidgetColorScheme.cardBgColor

    Text {
        id: timeLabel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.height * 0.12
        text: root.timeText
        font.family: nagasakiFont.name
        font.pixelSize: root.height * 0.8
        color: root.textColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    StyledDropShadow {
        target: timeLabel
        visible: Config.options.background.widgets.enableShadows ?? false
    }
}
