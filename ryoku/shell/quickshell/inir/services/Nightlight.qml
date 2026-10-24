pragma Singleton

import QtQuick
import Quickshell
import shell.services as Ryoku

// Night-light bridge. Ryoku's daemon owns the light: on/off, warmth and the
// sunset-to-sunrise schedule. The frame's toggles, warmth slider and schedule
// switch drive it here, so they change the screen instead of a frame-only key.
Singleton {
    id: root

    readonly property bool active: Ryoku.Nightlight.on
    readonly property int temperature: Ryoku.Nightlight.temperature
    // The frame's switch owns the sun schedule; the Hub can also run the
    // light on the clock, which this row reports but does not edit.
    readonly property bool scheduled: Ryoku.Nightlight.schedule === "sun"
    readonly property bool clocked: Ryoku.Nightlight.schedule === "clock"

    function toggle(): void { Ryoku.Nightlight.setEnabled(!root.active, root.temperature); }
    function setActive(on: bool): void { Ryoku.Nightlight.setEnabled(on, root.temperature); }
    function setTemperature(kelvin: int): void { Ryoku.Nightlight.setTemperature(kelvin); }
    function setScheduled(on: bool): void { Ryoku.Nightlight.setSchedule(on); }
}
