pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import stage.services
import ".."

CalendarEngine {
    preferredCalendar: Config.ready ? String(Config.options.calendar.timetable.defaultCalendar ?? "") : ""

    onDefaultCalendarSelected: name => {
        if (Config.ready && Config.options.calendar.timetable.defaultCalendar !== name)
            Config.options.calendar.timetable.defaultCalendar = name;
    }
}
