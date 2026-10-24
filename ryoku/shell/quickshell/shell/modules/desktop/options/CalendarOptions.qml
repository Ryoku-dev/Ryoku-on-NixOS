pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons

// Right-click options for Ryoku's native Calendar: the grid controls the removed
// Hub Widgets page owned. Style, size, opacity, placement and lock stay in
// WidgetMenu's generic rows. Writes land on the same widgets.json Config.
Column {
    id: opts

    property string widget: ""

    width: parent ? parent.width : 0
    spacing: Theme.s1

    MenuSection { label: I18n.tr("Calendar"); gloss: "暦" }
    MenuSlider {
        id: weeks
        // Fewest week rows; the month grows the view when it needs more.
        label: I18n.tr("Minimum weeks")
        from: 4
        to: 8
        step: 1
        value: Config.calendarWeeks
        valueText: Math.round(weeks.value)
        onMoved: (v) => Config.setLive("calendarWeeks", Math.round(v))
        onReleased: (v) => Config.set("calendarWeeks", Math.round(v))
    }
    MenuRow {
        label: I18n.tr("ISO week numbers")
        value: Config.calendarWeekNumbers ? I18n.tr("On") : I18n.tr("Off")
        on: Config.calendarWeekNumbers
        closeOnTrigger: false
        onTriggered: Config.toggle("calendarWeekNumbers")
    }
    MenuTextField {
        // Blank follows the locale; else a region code like US or US-CA.
        label: I18n.tr("Holiday region")
        placeholder: I18n.tr("Locale (e.g. US, US-CA)")
        text: Config.calendarHolidayRegion
        onCommitted: (v) => Config.set("calendarHolidayRegion", v)
    }
}
