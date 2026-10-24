.pragma library

// The widget scopes (Ryoku keys) that ship a right-click options panel. The
// menu resolves each panel by name -- options/<Capitalised scope>Options.qml --
// so registering a new one is a new file plus one line here, and no two owners
// have to touch WidgetMenu.qml. Keep entries one-per-line so appends never
// collide.
var _has = {
    // Canvas widgets (MenuSide).
    "irisJp": true,
    "irisCustomImage": true,
    "irisEditorial": true,
    "irisConverter": true,
    // Native widgets + iRiS faces (FaceMenus).
    "clock": true,
    "calendar": true,
    "music": true,
    "notes": true,
    "irisClock": true,
    "irisWeather": true,
    "irisMedia": true,
    "irisMonth": true,
    "irisAgenda": true,
    "irisTodo": true,
    "irisNotes": true,
    "irisTimers": true,
    "irisVitals": true,
    "irisBattery": true,
    "irisWorld": true,
    "irisDate": true,
    "irisProfile": true,
    "irisUptime": true,
    "irisNews": true,
    "irisVisualizer": true,
    "visualizer": true,
    // Python faces (PythonRoster + the options/Python* panels).
    "pythonTime": true,
    "pythonMusic": true,
    "pythonImage": true,
    "pythonGithub": true,
    "pythonCpu": true,
    "pythonRam": true,
    "pythonTemp": true,
    "pythonDisk": true,
    "pythonBattery": true,
    "pythonVisualizer": true,
};

var _panel = {
    "pythonCpu": "PythonCircleOptions.qml",
    "pythonRam": "PythonCircleOptions.qml",
    "pythonTemp": "PythonCircleOptions.qml",
    "pythonDisk": "PythonCircleOptions.qml",
    "pythonBattery": "PythonCircleOptions.qml"
};

function has(widget) {
    return _has[widget] === true;
}

function panelFile(widget) {
    return _panel[widget] || "";
}
