.pragma library

// The vendored iRiS desktop widgets that join Ryoku's roster. `kind` is "face"
// (a widget with an irisFace, hosted as its face) or "canvas" (a widget with no
// face, hosted whole). id is the inir gallery id (drives the provider + the
// widget's configEntryName); prefix is the Ryoku widgets.json key stem; gloss is
// the kanji seal the right-click menu wears; sizes is the face's own iRiS size
// ladder (a size control shows only when it has more than one; canvas widgets
// have none).
var faces = [
    { id: "clock",            prefix: "irisClock",    label: "Clock",       icon: "schedule",          gloss: "時計", kind: "face",   sizes: ["small", "medium"] },
    { id: "weather",          prefix: "irisWeather",  label: "Weather",     icon: "partly_cloudy_day", gloss: "天気", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "mediaControls",    prefix: "irisMedia",    label: "Now Playing", icon: "music_note",        gloss: "音楽", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "controls",         prefix: "irisControls", label: "Controls",    icon: "toggle_on",         gloss: "操作", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "monthCalendar",    prefix: "irisMonth",    label: "Calendar",    icon: "calendar_month",    gloss: "暦",   kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "calendarUpcoming", prefix: "irisAgenda",   label: "Up next",     icon: "event_upcoming",    gloss: "予定", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "todo",             prefix: "irisTodo",     label: "Tasks",       icon: "checklist",         gloss: "課題", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "notes",            prefix: "irisNotes",    label: "Notes",       icon: "sticky_note_2",     gloss: "筆記", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "timers",           prefix: "irisTimers",   label: "Timers",      icon: "timer",             gloss: "計時", kind: "face",   sizes: ["small", "medium"] },
    { id: "screenTime",       prefix: "irisScreen",   label: "Screen Time", icon: "hourglass_bottom",  gloss: "時間", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "systemMonitor",    prefix: "irisVitals",   label: "Vitals",      icon: "monitor_heart",     gloss: "計測", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "battery",          prefix: "irisBattery",  label: "Batteries",   icon: "battery_full",      gloss: "電池", kind: "face",   sizes: ["small", "medium"] },
    { id: "worldClock",       prefix: "irisWorld",    label: "World clock", icon: "public",            gloss: "世界", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "dateBadge",        prefix: "irisDate",     label: "Date",        icon: "today",             gloss: "日付", kind: "face",   sizes: ["small"] },
    { id: "userCard",         prefix: "irisProfile",  label: "Profile",     icon: "account_circle",    gloss: "人物", kind: "face",   sizes: ["small", "medium"] },
    { id: "uptime",           prefix: "irisUptime",   label: "Uptime",      icon: "timelapse",         gloss: "稼働", kind: "face",   sizes: ["small"] },
    { id: "newsTicker",       prefix: "irisNews",     label: "News",        icon: "newspaper",         gloss: "報道", kind: "face",   sizes: ["small", "medium", "large"] },
    { id: "customImage",        prefix: "irisCustomImage", label: "Custom Image",    icon: "image",     gloss: "画像", kind: "canvas", sizes: [] },
    { id: "editorial",          prefix: "irisEditorial",   label: "Editorial",       icon: "article",   gloss: "社説", kind: "canvas", sizes: [] },
    { id: "imageConverter",     prefix: "irisConverter",   label: "Image Converter", icon: "sync_alt",  gloss: "変換", kind: "canvas", sizes: [] },
    { id: "japaneseTypography", prefix: "irisJp",          label: "Japanese Type",   icon: "translate", gloss: "縦書", kind: "canvas", sizes: [] },
    { id: "visualizer",         prefix: "irisVisualizer",  label: "Shima Visualizer", icon: "graphic_eq", gloss: "音波", kind: "canvas", sizes: [] }
];

// Prefix -> face record, for the menu and Hub.
function byPrefix(prefix) {
    for (var i = 0; i < faces.length; i++)
        if (faces[i].prefix === prefix)
            return faces[i];
    return null;
}

function isIris(prefix) {
    return byPrefix(prefix) !== null;
}
