pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import shell.services

/**
 * Local screen-time tracking. Focus changes bank the elapsed interval against
 * today's bucket (per app, per hour, and a running total). "Active" means a
 * real app is focused; nothing syncs and nothing leaves the box. History persists
 * to ~/.local/state/ryoku/screentime.json (last 30 days), so a shell restart
 * resumes the same day.
 */
Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property int sampleSec: 10

    // { "YYYY-MM-DD": { total: int, apps: { class: sec }, hours: [24 ints], appHours: { class: [24 ints] } } }
    property var days: ({})
    property string today: ""
    property bool dirty: false
    property string focusedClass: ""
    property real focusSinceMs: 0

    readonly property var todayEntry: root.days[root.today] || null
    readonly property int activeToday: root.todayEntry ? (root.todayEntry.total || 0) : 0

    // Top apps today, resolved to a display name + icon, most used first.
    readonly property var topApps: {
        const e = root.todayEntry;
        if (!e || !e.apps)
            return [];
        const arr = [];
        for (const cls in e.apps)
            arr.push({ cls: cls, seconds: e.apps[cls] });
        arr.sort((a, b) => b.seconds - a.seconds);
        return arr.slice(0, 6).map(function (a) {
            const entry = (typeof DesktopEntries !== "undefined" && DesktopEntries.heuristicLookup)
                ? DesktopEntries.heuristicLookup(a.cls) : null;
            return {
                cls: a.cls,
                seconds: a.seconds,
                name: (entry && entry.name) ? entry.name : root.prettyClass(a.cls),
                icon: (entry && entry.icon) ? Icons.path(entry.icon, true) : ""
            };
        });
    }
    readonly property int topSeconds: root.topApps.length > 0 ? root.topApps[0].seconds : 1

    // Last seven days including today, oldest first, for the trend bars.
    readonly property var weekly: {
        const out = [];
        const now = new Date();
        const dow = ["S", "M", "T", "W", "T", "F", "S"];
        for (let i = 6; i >= 0; i--) {
            const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i);
            const key = root.dateKey(d);
            const e = root.days[key];
            out.push({ key: key, label: dow[d.getDay()], total: e ? (e.total || 0) : 0, isToday: i === 0 });
        }
        return out;
    }
    readonly property int weeklyMax: {
        let m = 1;
        for (let i = 0; i < root.weekly.length; i++)
            m = Math.max(m, root.weekly[i].total);
        return m;
    }

    function dateKey(d) {
        const m = ("0" + (d.getMonth() + 1)).slice(-2);
        const day = ("0" + d.getDate()).slice(-2);
        return d.getFullYear() + "-" + m + "-" + day;
    }
    function prettyClass(c) {
        const s = ("" + c).split(".").pop();
        return s.length > 0 ? s.charAt(0).toUpperCase() + s.slice(1) : c;
    }
    function fmtDuration(sec) {
        sec = Math.max(0, Math.floor(sec));
        const h = Math.floor(sec / 3600);
        const m = Math.floor((sec % 3600) / 60);
        if (h > 0)
            return I18n.tr("%1h %2m").arg(h).arg(m);
        if (m > 0)
            return I18n.tr("%1m").arg(m);
        return I18n.tr("%1s").arg(sec);
    }
    function isRealApp(c) {
        return !!c && !/^(ryoku|quickshell|org\.quickshell)/i.test(c);
    }
    function zeros24() {
        const a = [];
        for (let i = 0; i < 24; i++)
            a.push(0);
        return a;
    }

    function addSeconds(c, seconds, at) {
        if (!root.isRealApp(c) || seconds <= 0)
            return;
        const key = root.dateKey(at);
        const prev = root.days[key] || { total: 0, apps: ({}), hours: root.zeros24() };
        const entry = {
            total: (prev.total || 0) + seconds,
            apps: Object.assign({}, prev.apps),
            hours: (prev.hours && prev.hours.length === 24) ? prev.hours.slice() : root.zeros24(),
            appHours: Object.assign({}, prev.appHours)
        };
        entry.apps[c] = (entry.apps[c] || 0) + seconds;
        const hour = at.getHours();
        entry.hours[hour] = (entry.hours[hour] || 0) + seconds;
        const appHours = (entry.appHours[c] && entry.appHours[c].length === 24)
            ? entry.appHours[c].slice() : root.zeros24();
        appHours[hour] += seconds;
        entry.appHours[c] = appHours;
        const next = Object.assign({}, root.days);
        next[key] = entry;
        root.days = next;
        root.today = root.dateKey(new Date());
        root.dirty = true;
    }

    function accrue(c) {
        root.addSeconds(c, root.sampleSec, new Date());
        persistDebounce.restart();
    }

    function bankFocused() {
        const end = Date.now();
        if (root.focusSinceMs <= 0 || !root.isRealApp(root.focusedClass)) {
            root.focusSinceMs = end;
            return;
        }
        let cursor = root.focusSinceMs;
        while (cursor < end) {
            const at = new Date(cursor);
            const boundary = new Date(at.getFullYear(), at.getMonth(), at.getDate(),
                                      at.getHours() + 1, 0, 0, 0).getTime();
            const segmentEnd = Math.min(end, boundary);
            const seconds = Math.floor((segmentEnd - cursor) / 1000);
            root.addSeconds(root.focusedClass, seconds, at);
            cursor = segmentEnd;
        }
        root.focusSinceMs = end;
        if (root.dirty)
            persistDebounce.restart();
    }

    function focusChanged() {
        const next = Wm.focusedWindow ? Wm.focusedWindow.appId : "";
        if (next === root.focusedClass)
            return;
        root.bankFocused();
        root.focusedClass = next;
        root.focusSinceMs = Date.now();
    }

    function prune() {
        const keys = Object.keys(root.days).sort();
        if (keys.length <= 30)
            return;
        const d = Object.assign({}, root.days);
        for (let i = 0; i < keys.length - 30; i++)
            delete d[keys[i]];
        root.days = d;
    }
    function persist() {
        root.prune();
        file.setText(JSON.stringify({ days: root.days }));
        root.dirty = false;
    }
    function load(text) {
        try {
            const j = JSON.parse(text || "{}");
            root.days = (j && j.days) ? j.days : ({});
        } catch (e) {
            root.days = ({});
        }
        const key = root.dateKey(new Date());
        root.today = key;
        if (!root.days[key]) {
            const d = Object.assign({}, root.days);
            d[key] = { total: 0, apps: ({}), hours: root.zeros24() };
            root.days = d;
        }
        root.focusedClass = Wm.focusedWindow ? Wm.focusedWindow.appId : "";
        root.focusSinceMs = Date.now();
    }

    Connections {
        target: Wm
        function onFocusedWindowChanged() {
            root.focusChanged();
        }
    }

    Timer {
        id: persistDebounce
        interval: 1500
        onTriggered: if (root.dirty) root.persist()
    }

    Process {
        command: ["mkdir", "-p", root.stateDir]
        running: true
    }
    FileView {
        id: file
        path: root.stateDir + "/screentime.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.load(file.text())
        onLoadFailed: root.load("{}")
    }

    Component.onDestruction: {
        root.bankFocused();
        if (root.dirty)
            root.persist();
    }
}
