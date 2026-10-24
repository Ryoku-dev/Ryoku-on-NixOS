pragma Singleton
import QtQuick
import Quickshell
import shell.services
import "../../"

// Ryoku seam: serpantinum ran a per-monitor wl-gammarelay fleet of its own.
// Ryoku owns night light: the daemon holds the gamma (one warm-gamma claim per
// session, hotplug-safe) and the Hub's Displays page drives it. This keeps the
// surface API the ported guide and system panel call (per-monitor enabled /
// auto / temperature persisted under the style's own display settings, plus
// isAnyEnabled and settingsChanged), but the live gamma always rides the
// daemon's Nightlight service. The per-monitor choice is remembered for the
// style's UI; the applied warmth is the session-wide one Ryoku ships.
Item {
    id: root

    signal settingsChanged()

    property var defaultDisplaySettings: ({ "monitors": {} })

    readonly property bool on: Nightlight.on
    readonly property int temperature: Nightlight.temperature
    readonly property string schedule: Nightlight.schedule

    function displaySettings() {
        if (typeof Config === "undefined") return defaultDisplaySettings;
        let ds = Config.getSetting("display", defaultDisplaySettings);
        return ds ? ds : defaultDisplaySettings;
    }

    function isAnyEnabled() {
        let ds = displaySettings();
        if (ds.enabled === true) return true;
        if (ds.monitors) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                if (ds.monitors[keys[i]] && ds.monitors[keys[i]].enabled === true)
                    return true;
            }
        }
        return false;
    }

    function kelvinFromTemp(temp) {
        let t = (temp !== undefined && temp !== null) ? Number(temp) : 50;
        if (t >= 1000) {
            return Math.min(Math.max(Math.round(t), 1000), 10000);
        }
        return Math.round(6500 - (t / 100) * (6500 - 2500));
    }

    function getSavedTemperature(monName) {
        let ds = displaySettings();
        if (monName && ds.monitors && ds.monitors[monName] && ds.monitors[monName].temperature !== undefined) {
            return ds.monitors[monName].temperature;
        }
        if (ds.temperature !== undefined) return ds.temperature;
        return 50;
    }

    function getSavedAuto(monName) {
        let ds = displaySettings();
        if (monName && ds.monitors && ds.monitors[monName] && ds.monitors[monName].auto !== undefined) {
            return ds.monitors[monName].auto;
        }
        if (ds.auto !== undefined) return ds.auto;
        return false;
    }

    // Push the remembered style state onto the daemon's night light: on/off
    // with the warmest remembered temperature, and the sun schedule when any
    // monitor asked for automatic.
    function syncNightlight() {
        let ds = displaySettings();
        let anyEnabled = isAnyEnabled();
        let anyAuto = ds.auto === true;
        if (ds.monitors) {
            let keys = Object.keys(ds.monitors);
            for (let i = 0; i < keys.length; i++) {
                let m = ds.monitors[keys[i]];
                if (m && m.auto === true) anyAuto = true;
            }
        }
        let kelvin = 4000;
        if (anyEnabled) {
            let best = 0;
            let temps = [ds.temperature];
            if (ds.monitors) {
                let keys = Object.keys(ds.monitors);
                for (let i = 0; i < keys.length; i++)
                    temps.push(ds.monitors[keys[i]] ? ds.monitors[keys[i]].temperature : undefined);
            }
            for (let i = 0; i < temps.length; i++) {
                if (temps[i] !== undefined && Number(temps[i]) > best) best = Number(temps[i]);
            }
            kelvin = kelvinFromTemp(best > 0 ? best : 50);
        }
        Nightlight.setEnabled(anyEnabled, kelvin);
        Nightlight.setSchedule(anyEnabled && anyAuto);
    }

    function updateMonitorSetting(monName, key, value) {
        if (!monName) return;
        let current = JSON.parse(JSON.stringify(displaySettings()));
        if (!current.monitors) current.monitors = {};
        if (!current.monitors[monName]) current.monitors[monName] = {};
        current.monitors[monName][key] = value;
        if (typeof Config !== "undefined") Config.setSetting("display", current);
        syncNightlight();
        root.settingsChanged();
    }

    function setEnabled(monName, enabled) {
        if (typeof enabled === "undefined" && typeof monName === "boolean") {
            enabled = monName;
            monName = "";
        }
        if (!monName) {
            let current = JSON.parse(JSON.stringify(displaySettings()));
            current.enabled = enabled;
            if (current.monitors) {
                let keys = Object.keys(current.monitors);
                for (let i = 0; i < keys.length; i++)
                    current.monitors[keys[i]].enabled = enabled;
            }
            if (typeof Config !== "undefined") Config.setSetting("display", current);
            syncNightlight();
            root.settingsChanged();
            return;
        }
        updateMonitorSetting(monName, "enabled", enabled);
    }

    function setAuto(monName, autoMode) {
        if (typeof autoMode === "undefined" && typeof monName === "boolean") {
            autoMode = monName;
            monName = "";
        }
        if (!monName) {
            let current = JSON.parse(JSON.stringify(displaySettings()));
            current.auto = autoMode;
            if (current.monitors) {
                let keys = Object.keys(current.monitors);
                for (let i = 0; i < keys.length; i++)
                    current.monitors[keys[i]].auto = autoMode;
            }
            if (typeof Config !== "undefined") Config.setSetting("display", current);
            syncNightlight();
            root.settingsChanged();
            return;
        }
        updateMonitorSetting(monName, "auto", autoMode);
    }

    function setTemperature(monName, temp) {
        if (typeof temp === "undefined" && (typeof monName === "number" || typeof monName === "string")) {
            temp = monName;
            monName = "";
        }
        let numTemp = Number(temp);
        if (!monName) {
            let current = JSON.parse(JSON.stringify(displaySettings()));
            current.temperature = numTemp;
            if (current.monitors) {
                let keys = Object.keys(current.monitors);
                for (let i = 0; i < keys.length; i++)
                    current.monitors[keys[i]].temperature = numTemp;
            }
            if (typeof Config !== "undefined") Config.setSetting("display", current);
            syncNightlight();
            root.settingsChanged();
            return;
        }
        updateMonitorSetting(monName, "temperature", numTemp);
    }

    // The daemon's state is the truth for the shared light; re-emit so the
    // guide and the panel refresh their toggles when the Hub changes it.
    Connections {
        target: Nightlight
        function onOnChanged() { root.settingsChanged(); }
        function onTemperatureChanged() { root.settingsChanged(); }
        function onScheduleChanged() { root.settingsChanged(); }
    }
}
