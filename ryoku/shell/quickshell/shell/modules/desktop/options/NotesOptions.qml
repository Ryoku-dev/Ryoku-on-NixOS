pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons

// Right-click options for Ryoku's native Notes pad: its own pad dimensions, the
// one thing the Hub Widgets page set that WidgetMenu's generic size/opacity
// scale can't express (width and height are the pad's logical size before
// scale). Everything else stays in WidgetMenu's generic rows.
Column {
    id: opts

    property string widget: ""

    width: parent ? parent.width : 0
    spacing: Theme.s1

    MenuSection { label: I18n.tr("Notes"); gloss: "筆記" }
    MenuSlider {
        id: w
        label: I18n.tr("Width")
        from: 160
        to: 900
        step: 10
        value: Config.notesWidth
        valueText: Math.round(w.value)
        onMoved: (v) => Config.setLive("notesWidth", Math.round(v))
        onReleased: (v) => Config.set("notesWidth", Math.round(v))
    }
    MenuSlider {
        id: h
        label: I18n.tr("Height")
        from: 120
        to: 900
        step: 10
        value: Config.notesHeight
        valueText: Math.round(h.value)
        onMoved: (v) => Config.setLive("notesHeight", Math.round(v))
        onReleased: (v) => Config.set("notesHeight", Math.round(v))
    }
}
