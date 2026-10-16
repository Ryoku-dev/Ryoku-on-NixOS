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
    implicitWidth: configSize
    implicitHeight: configSize

    FontLoader {
        id: nagasakiFont
        source: "file://" + Directories.assetsPath + "/fonts/nagasaki.ttf"
    }

    readonly property string hour: DateTime.time.split(":")[0].padStart(2, "0")
    readonly property string minute: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
    readonly property string timeText: hour + minute

    readonly property color textColor: WidgetColorScheme.cardBgColor

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
