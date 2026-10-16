pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import stage
import stage.modules.common

// Water Reminder background widget service.
// Tracks daily glasses drunk and periodically sends a system notification
// every `intervalHours` until the daily goal is reached. The counter resets
// each day and persists across restarts via Persistent.state.
Singleton {
    id: root

    readonly property bool configured: Config.ready
    readonly property bool enabled: configured && (Config.options.background.widgets.water_reminder.enable ?? false)
    readonly property int dailyGoal: configured ? (Config.options.background.widgets.water_reminder.dailyGoal || 8) : 8
    readonly property int intervalHours: configured ? (Config.options.background.widgets.water_reminder.intervalHours || 2) : 2

    property int glassesDrunk: 0
    property bool goalReached: dailyGoal > 0 && glassesDrunk >= dailyGoal
    property string _lastDate: ""
    property real _lastNotify: 0
    // Glasses per day, last 14 days, today included.
    property var history: ({})

    function _todayKey() {
        const d = new Date();
        return root._keyFor(d);
    }

    function _keyFor(date) {
        return date.getFullYear() + "-" + (date.getMonth() + 1) + "-" + date.getDate();
    }

    function _save() {
        if (!Persistent.ready)
            return;
        const water = Persistent.states.water;
        water.glassesDrunk = root.glassesDrunk;
        water.lastDate = root._lastDate;
        water.lastNotify = root._lastNotify;

        const next = {};
        const oldest = new Date();
        oldest.setDate(oldest.getDate() - 13);
        const keep = {};
        for (let date = new Date(oldest); date <= new Date(); date.setDate(date.getDate() + 1))
            keep[root._keyFor(date)] = true;
        for (const key in root.history) {
            if (keep[key])
                next[key] = root.history[key];
        }
        if (root._lastDate.length > 0)
            next[root._lastDate] = root.glassesDrunk;
        root.history = next;
        water.historyJson = JSON.stringify(next);
    }

    /** The last seven days, oldest first: [{ date, glasses }]. */
    function week() {
        const out = [];
        for (let offset = 6; offset >= 0; offset--) {
            const date = new Date();
            date.setDate(date.getDate() - offset);
            const key = root._keyFor(date);
            out.push({
                date: date,
                glasses: key === root._lastDate ? root.glassesDrunk : Number(root.history[key] ?? 0)
            });
        }
        return out;
    }

    function ensureToday() {
        if (root._lastDate === root._todayKey())
            return;
        root.glassesDrunk = 0;
        root._lastDate = root._todayKey();
        root._save();
    }

    /** Add or take back glasses without capping the dock and water-glass faces at the goal. */
    function drink(delta) {
        root.ensureToday();
        const before = root.glassesDrunk;
        root.glassesDrunk = Math.max(0, root.glassesDrunk + Number(delta || 0));
        root._save();
        if (delta > 0 && before < root.dailyGoal && root.glassesDrunk >= root.dailyGoal)
            root._notifyGoal();
    }

    function _load() {
        if (!Persistent.ready)
            return;
        const water = Persistent.states.water || {};
        try {
            const parsed = JSON.parse(water.historyJson || "{}");
            root.history = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
        } catch (error) {
            root.history = {};
        }
        root._lastDate = water.lastDate || "";
        root._lastNotify = water.lastNotify || 0;
        if (root._lastDate !== root._todayKey()) {
            root.glassesDrunk = 0;
            root._lastDate = root._todayKey();
            root._save();
        } else {
            root.glassesDrunk = Math.max(0, water.glassesDrunk || 0);
        }
    }

    // The compact reminder face resets after its goal; the dock and water-glass
    // face call drink() directly and may continue above the goal.
    function addGlass() {
        root.ensureToday();
        if (root.dailyGoal <= 0)
            return;
        if (root.glassesDrunk >= root.dailyGoal) {
            root.resetCounter();
            return;
        }
        root.drink(1);
    }

    function resetCounter() {
        root.ensureToday();
        root.glassesDrunk = 0;
        root._save();
    }

    function _notifyGoal() {
        Quickshell.execDetached([
            "notify-send",
            "-a", Translation.tr("Water Reminder"),
            Translation.tr("Daily water goal reached!"),
            Translation.tr("You drank %1 glasses today.").arg(String(root.dailyGoal))
        ]);
    }

    function _notify() {
        const note = Config.options.background.widgets.water_reminder.reminderText
            || Translation.tr("Time to hydrate! 💧");
        Quickshell.execDetached([
            "notify-send",
            "-a", Translation.tr("Water Reminder"),
            "-i", "water_drop",
            note
        ]);
    }

    function _check() {
        if (Persistent.ready)
            root.ensureToday();
        if (!root.enabled)
            return;
        if (root.dailyGoal > 0 && root.glassesDrunk >= root.dailyGoal)
            return;

        const intervalMs = Math.max(1, root.intervalHours) * 3600 * 1000;
        const now = Date.now();
        if (root._lastNotify <= 0 || now - root._lastNotify >= intervalMs) {
            root._lastNotify = now;
            root._save();
            root._notify();
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root._check()
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready)
                root._load();
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready)
                root._load();
        }
    }

    Component.onCompleted: {
        if (Config.ready && Persistent.ready)
            root._load();
    }
}
