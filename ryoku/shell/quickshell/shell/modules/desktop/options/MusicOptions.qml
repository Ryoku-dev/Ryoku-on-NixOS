pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons

// Right-click options for Ryoku's native Music sheet. Style, lyrics, visualiser,
// canvas, backdrop and video/GIF are already WidgetMenu generic rows; the one
// Hub-only setting left is the launch target for the sheet's corner app button.
Column {
    id: opts

    property string widget: ""

    width: parent ? parent.width : 0
    spacing: Theme.s1

    MenuSection { label: I18n.tr("Music"); gloss: "音楽" }
    MenuTextField {
        // Command the sheet's corner button launches; blank opens the default
        // media handler.
        label: I18n.tr("Music app")
        placeholder: I18n.tr("Launch command")
        text: Config.musicApp
        onCommitted: (v) => Config.set("musicApp", v)
    }
}
