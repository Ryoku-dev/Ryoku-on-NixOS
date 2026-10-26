pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import inir.services
import inir.modules.common
import shell.services as Ryoku

// Notifications bridge. Ryoku's shell owns the freedesktop server and its
// model (shell.services Notifs); the frame reads the reference's wrapper shape
// (Notif objects with notificationId/actions/popup flags and the group API)
// on top of it, so no second notification server ever registers.
Singleton {
    id: root

    property var list: []
    property var popupList: []
    property int unread: root.popupList.length

    signal notify(notification: var)
    signal discard(id: int)
    signal discardAll()
    signal initDone()

    // id -> wrapper; rebuilt whenever the shell model churns.
    property var _byId: ({})

    function _wrap(n, popup) {
        return {
            notificationId: n.id,
            notification: n,
            actions: (n.actions ?? []).map(a => ({ identifier: a.identifier ?? a,
                text: String(a.text ?? "").trim().length === 0 && String(a.identifier ?? a) === "default"
                    ? Translation.tr("Open") : (a.text ?? String(a)) })),
            popup: popup === true,
            isTransient: true,
            appIcon: n.appIcon ?? "",
            appName: n.appName ?? "",
            body: n.body ?? "",
            image: "",
            summary: n.summary ?? "",
            time: Number(Ryoku.Notifs.arrivalMs[n.id] ?? Date.now()),
            urgency: String(n.urgency ?? "normal")
        };
    }

    // iRiS expects oldest-first groups and reads each tail as the newest notification.
    function _rebuild() {
        const popups = Ryoku.Notifs.popups ?? [];
        const popupIds = {};
        for (const p of popups)
            popupIds[p.id] = true;
        const seen = {};
        const out = [];
        for (const n of popups.concat(Ryoku.Notifs.history ?? [])) {
            if (seen[n.id])
                continue;
            seen[n.id] = true;
            out.push(root._wrap(n, popupIds[n.id] === true));
        }
        out.sort((a, b) => a.time - b.time);
        root.list = out;
        root.popupList = out.filter(w => w.popup);
        const byId = {}
        for (const w of out)
            byId[w.notificationId] = w
        root._byId = byId
    }

    // Rebuild on any change of either shell list.
    property var _watchHistory: Ryoku.Notifs.history
    property var _watchPopups: Ryoku.Notifs.popups
    on_WatchHistoryChanged: _rebuild()
    on_WatchPopupsChanged: _rebuild()
    Component.onCompleted: {
        _rebuild()
    }

    // ---- group model ----
    function _normalizeAppKey(name) {
        return String(name ?? "").trim().toLowerCase();
    }

    readonly property var groupsByAppName: {
        const groups = {};
        for (const w of root.list) {
            const key = root._normalizeAppKey(w.appName);
            if (key.length === 0)
                continue;
            if (!groups[key])
                groups[key] = { appName: w.appName, notifications: [], unreadCount: 0, latest: null };
            groups[key].notifications.push(w);
            if (w.popup)
                groups[key].unreadCount++;
            if (!groups[key].latest || w.time > groups[key].latest.time)
                groups[key].latest = w;
        }
        return groups;
    }

    readonly property var appNameList: Object.keys(root.groupsByAppName)
        .sort((a, b) => root.groupsByAppName[b].latest.time - root.groupsByAppName[a].latest.time)

    // ---- mutations ----
    function dismissWrapper(w) {
        const n = w?.notification;
        if (n && typeof n.dismiss === "function")
            n.dismiss();
        else if (n && typeof n.close === "function")
            n.close();
        if (n && typeof n.dismissExpired === "function")
            n.dismissExpired();
    }

    function discardNotification(id) {
        const w = root._byId[id];
        if (!w)
            return;
        root.dismissWrapper(w);
        root.discard(Number(id));
    }

    function discardNotificationsForApp(appName) {
        const g = root.groupsByAppName[root._normalizeAppKey(appName)];
        for (const w of (g?.notifications ?? []).slice())
            root.dismissWrapper(w);
    }

    function discardAllNotifications() {
        Ryoku.Notifs.clearAll();
        root.discardAll();
    }

    function timeoutNotification(id) {
        root.discardNotification(id);
    }

    function timeoutAll() {
        for (const w of root.popupList.slice())
            root.discardNotification(w.notificationId);
    }

    function attemptInvokeAction(notificationId, actionId) {
        const n = root._byId[notificationId]?.notification;
        const actions = n?.actions ?? [];
        for (const a of actions) {
            const ident = a.identifier ?? a;
            if (String(ident) === String(actionId) && typeof a.invoke === "function") {
                a.invoke();
                return;
            }
        }
    }

    function cancelTimeout(id) {
    }

    // ---- DND and mute ----
    readonly property bool manualDndActive: Ryoku.Notifs.dnd === true
    readonly property bool silent: manualDndActive

    function toggleSilent() {
        Ryoku.Flags.dnd = !Ryoku.Flags.dnd;
    }

    function markAllRead() {
        root.timeoutAll();
    }
}
