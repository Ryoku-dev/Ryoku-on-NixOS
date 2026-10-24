pragma ComponentBehavior: Bound
import QtQuick
import inir.modules.background.widgets.clock
import inir.modules.background.widgets.weather
import inir.modules.background.widgets.mediaControls
import inir.modules.background.widgets.controls
import inir.modules.background.widgets.calendar
import inir.modules.background.widgets.todo
import inir.modules.background.widgets.notes
import inir.modules.background.widgets.timers
import inir.modules.background.widgets.screenTime
import inir.modules.background.widgets.systemMonitor
import inir.modules.background.widgets.battery
import inir.modules.background.widgets.worldClock
import inir.modules.background.widgets.dateBadge
import inir.modules.background.widgets.userCard
import inir.modules.background.widgets.uptime
import inir.modules.background.widgets.newsTicker

// Hidden host for one vendored iRiS background widget. It builds the concrete
// AbstractBackgroundWidget subclass purely as a data + face source: the widget
// itself never paints (it lives inside this zero-size, non-rendering Item), so
// none of its own canvas chrome, placement or edit machinery reaches the
// screen. Ryoku's WidgetSlot owns placement/lock/persistence; this feeds the
// widget the screen metrics it needs (including its real on-screen position via
// hostX/hostY, so a glass iNiR face still crops the wallpaper under it) and the
// Ryoku host hooks. ryokuStyle picks the additive Ryoku skin PER WIDGET; when it
// is off the face renders exactly as upstream iNiR. The face captured on the
// widget (`widget.irisFace`) is rendered by whoever owns this provider.
Item {
    id: prov

    // One of the gallery ids: clock weather mediaControls controls monthCalendar
    // calendarUpcoming todo notes timers screenTime systemMonitor battery
    // worldClock dateBadge userCard uptime newsTicker.
    property string faceId: "clock"
    property int screenW: 1920
    property int screenH: 1080
    property string outputName: ""
    // The face's real top-left in the desktop layer (screen logical px).
    property real hostX: 0
    property real hostY: 0

    // Additive Ryoku skin for this widget (per-widget, never global frontend).
    property bool ryokuStyle: false
    // Ryoku host overrides, forwarded into the widget's inert hooks.
    property color inkOverride: "transparent"
    property color accentOverride: "transparent"
    property string sizeOverride: ""
    property real scaleOverride: -1
    property real radiusOverride: -1
    property var optionOverrides: ({})

    // The live widget instance (null until the loader resolves).
    readonly property var widget: host.item

    visible: false
    width: 0
    height: 0

    function _componentFor(id: string): Component {
        switch (id) {
        case "clock": return cClock;
        case "weather": return cWeather;
        case "mediaControls": return cMedia;
        case "controls": return cControls;
        case "monthCalendar": return cMonth;
        case "calendarUpcoming": return cAgenda;
        case "todo": return cTodo;
        case "notes": return cNotes;
        case "timers": return cTimers;
        case "screenTime": return cScreen;
        case "systemMonitor": return cVitals;
        case "battery": return cBattery;
        case "worldClock": return cWorld;
        case "dateBadge": return cDate;
        case "userCard": return cProfile;
        case "uptime": return cUptime;
        case "newsTicker": return cNews;
        }
        return null;
    }

    Loader {
        id: host
        active: true
        sourceComponent: prov._componentFor(prov.faceId)
    }

    Component { id: cClock; ClockWidget { configEntryName: "clock"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cWeather; WeatherWidget { configEntryName: "weather"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cMedia; MediaControlsWidget { configEntryName: "mediaControls"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cControls; ControlsWidget { configEntryName: "controls"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cMonth; MonthCalendarWidget { configEntryName: "monthCalendar"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cAgenda; CalendarUpcomingWidget { configEntryName: "calendarUpcoming"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cTodo; TodoWidget { configEntryName: "todo"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cNotes; NotesWidget { configEntryName: "notes"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cTimers; TimerWidget { configEntryName: "timers"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cScreen; ScreenTimeWidget { configEntryName: "screenTime"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cVitals; SystemMonitorWidget { configEntryName: "systemMonitor"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cBattery; BatteryWidget { configEntryName: "battery"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cWorld; WorldClockWidget { configEntryName: "worldClock"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cDate; DateBadgeWidget { configEntryName: "dateBadge"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cProfile; UserCardWidget { configEntryName: "userCard"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cUptime; UptimeWidget { configEntryName: "uptime"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
    Component { id: cNews; NewsTickerWidget { configEntryName: "newsTicker"; visible: false; ryokuHosted: true; ryokuStyle: prov.ryokuStyle; outputName: prov.outputName; screenWidth: prov.screenW; screenHeight: prov.screenH; scaledScreenWidth: prov.screenW; scaledScreenHeight: prov.screenH; wallpaperScale: 1; ryokuHostX: prov.hostX; ryokuHostY: prov.hostY; ryokuInkOverride: prov.inkOverride; ryokuAccentOverride: prov.accentOverride; ryokuSizeOverride: prov.sizeOverride; ryokuScaleOverride: prov.scaleOverride; ryokuRadiusOverride: prov.radiusOverride; ryokuOptionOverrides: prov.optionOverrides } }
}
