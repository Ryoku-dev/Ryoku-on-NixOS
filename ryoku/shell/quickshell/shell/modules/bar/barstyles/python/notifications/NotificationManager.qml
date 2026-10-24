pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import shell.services

// Ryoku seam: the notification server is the shell's own (shell.services
// Notifs); a bar style never claims the D-Bus name twice. This keeps the
// serpantinum model shapes (uid-keyed ListModels, app grouping, the popup
// queue) fed from the shell's live history and popup lists instead of a
// private NotificationServer.
Item {
    id: root

    property var liveNotifs: ({})
    property bool isStartup: true
    property bool sysPanelOpen: false
    property real lastNotifTime: 0
    property bool _isBatchUpdating: false

    ListModel { id: historyModel }
    ListModel { id: popupsModel }
    ListModel { id: groupedHistoryModel }

    property alias globalNotificationHistory: historyModel
    property alias activePopupsModel: popupsModel
    property alias groupedHistory: groupedHistoryModel

    property var _resolveCache: ({})
    property var manualAliasTable: ({
        "telegram": "org.telegram.desktop",
        "discord": "discord",
        "slack": "slack",
        "spotify": "spotify"
    })

    signal popupAdded(int uid, var notif)

    onSysPanelOpenChanged: {
        if (sysPanelOpen) {
            popupsModel.clear();
            _resolveCache = {};
            requeue++;
        }
    }

    // Bumped whenever the shell's lists change; the sync timer coalesces a
    // burst of frames into one model rebuild.
    property int requeue: 0
    Timer {
        id: syncTimer
        interval: 60
        onTriggered: root.sync()
    }

    Timer {
        id: startupGraceTimer
        interval: 500
        running: true
        onTriggered: root.isStartup = false
    }

    function resolveApp(n) {
        if (!n) return { groupKey: "system", displayName: "System", icon: "", desktopEntry: null };

        let rawAppName = n.appName || "";
        let appName = rawAppName.toLowerCase().trim();
        appName = appName.replace(/\s*(canary|beta|nightly|-git|git|dev|development)\s*$/g, "");

        let desktopEntry = (n.desktopEntry || "").trim();
        let key = (desktopEntry + "|" + appName);
        if (_resolveCache[key] !== undefined) return _resolveCache[key];

        let entry = null;
        if (desktopEntry) {
            entry = DesktopEntries.byId(desktopEntry);
        }
        if (!entry && appName) {
            let alias = manualAliasTable[appName];
            if (alias) {
                entry = DesktopEntries.byId(alias);
            } else {
                entry = DesktopEntries.heuristicLookup(rawAppName);
            }
        }

        let resolved = {
            groupKey: entry ? entry.id : (appName || "system"),
            displayName: entry ? entry.name : (rawAppName || "System"),
            icon: n.appIcon || (entry ? entry.icon : ""),
            desktopEntry: entry
        };
        _resolveCache[key] = resolved;
        return resolved;
    }

    function extractActions(n) {
        let out = [];
        if (n && n.actions) {
            for (let i = 0; i < n.actions.length; i++) {
                out.push({
                    "id": n.actions[i].identifier || "",
                    "text": n.actions[i].text || n.actions[i].name || "Action"
                });
            }
        }
        return out;
    }

    function rowFor(n, uid) {
        let extracted = extractActions(n);
        let now = Notifs.arrivalMs[n.id] || Date.now();
        let summaryText = n.summary !== "" ? n.summary : "No Title";
        let bodyText = n.body !== "" ? n.body : "";
        let imageVal = (n.image ? n.image.toString() : "") || (n.imagePath ? n.imagePath.toString() : "") || (n.appIcon ? n.appIcon.toString() : "");
        return {
            "uid": uid,
            "id": n.id !== undefined && n.id !== null ? n.id : uid,
            "appName": n.appName !== "" ? n.appName : "System",
            "summary": summaryText,
            "body": bodyText,
            "iconPath": n.appIcon !== "" ? n.appIcon : "",
            "image": imageVal,
            "imagePath": imageVal,
            "actionsJson": JSON.stringify(extracted),
            "hasActions": extracted.length > 0,
            "notif": n,
            "timestamp": now,
            "urgency": n.urgency !== undefined && n.urgency !== null ? n.urgency : 0,
            "read": false
        };
    }

    // Reconcile the uid-keyed models against the shell's live lists. Uids are
    // the shell ids, stable across frames. Rows are updated in place (only
    // changed properties are written, and only vanished/new rows move), so a
    // popup expiry never destroys and re-creates every banner delegate.
    //
    // A notification can be closed by its sender between the daemon frame and
    // this rebuild (a screenshot toast ryoshot dismisses on its own); reading a
    // retired wrapper yields undefined fields, and appending an all-undefined
    // row corrupts the model's roles and crashes the shell. Rows without a uid
    // or id are dropped outright.
    function rowIsSane(row) {
        return row && row.uid !== undefined && row.uid !== null
            && row.id !== undefined && row.id !== null;
    }

    function reconcile(model, rows) {
        var keep = ({});
        for (let i = 0; i < rows.length; i++) keep[rows[i].uid] = true;
        for (let i = model.count - 1; i >= 0; i--) {
            let cur = model.get(i);
            if (!cur || keep[cur.uid] === undefined) model.remove(i, 1);
        }
        for (let i = 0; i < rows.length; i++) {
            let want = rows[i];
            let cur = i < model.count ? model.get(i) : null;
            if (cur && cur.uid === want.uid) {
                for (let k in want) {
                    if (cur[k] !== want[k]) model.setProperty(i, k, want[k]);
                }
            } else {
                model.insert(i, want);
            }
        }
    }

    function sync() {
        let hist = Notifs.history;
        let pops = Notifs.popups;

        var live = ({});

        var nextHist = [];
        for (let i = 0; i < hist.length; i++) {
            let n = hist[i];
            if (!n) continue;
            let uid = n.id;
            if (uid === undefined || uid === null) continue;
            live[uid] = n;
            let existing = historyRow(uid);
            let row = existing || rowFor(n, uid);
            if (rowIsSane(row)) nextHist.push(row);
        }
        for (let i = 0; i < pops.length; i++) {
            let n = pops[i];
            if (n && n.id !== undefined && n.id !== null) live[n.id] = n;
        }

        root.liveNotifs = live;

        root._isBatchUpdating = true;
        reconcile(historyModel, nextHist);

        // Popups: serpantinum suppresses its own banners while the system
        // panel is open and during the startup grace.
        var nextPopups = [];
        if (!root.isStartup && !root.sysPanelOpen) {
            for (let i = 0; i < pops.length; i++) {
                let n = pops[i];
                if (!n) continue;
                let uid = n.id;
                if (uid === undefined || uid === null) continue;
                let row = historyRow(uid) || rowFor(n, uid);
                if (!rowIsSane(row)) continue;
                let resolved = resolveApp(n);
                nextPopups.push({
                    "uid": uid,
                    "latestUid": uid,
                    "uidsJson": JSON.stringify([uid]),
                    "groupKey": resolved.groupKey,
                    "displayName": resolved.displayName,
                    "icon": resolved.icon || row.iconPath,
                    "image": row.image,
                    "imagePath": row.imagePath,
                    "summary": row.summary,
                    "body": row.body,
                    "combinedBody": row.body,
                    "messagesJson": JSON.stringify(row.body !== "" ? [row.body] : []),
                    "messagesCount": 1,
                    "iconPath": row.iconPath,
                    "actionsJson": row.actionsJson,
                    "hasActions": row.hasActions,
                    "urgency": row.urgency,
                    "timestamp": row.timestamp
                });
            }
        }
        reconcile(popupsModel, nextPopups);
        root._isBatchUpdating = false;

        root.rebuildGroups();
    }

    function historyRow(uid) {
        for (let i = 0; i < historyModel.count; i++) {
            let r = historyModel.get(i);
            if (r && r.uid === uid) return historyModel.get(i);
        }
        return undefined;
    }

    function markGroupRead(groupKey) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let resolved = resolveApp(nData);
            let gKey = resolved.groupKey;
            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }
            if (gKey === groupKey && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
            }
        }
        if (changed) rebuildGroups();
    }

    function markAsRead(uid) {
        let changed = false;
        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (nData && nData.uid === uid && !nData.read) {
                historyModel.setProperty(i, "read", true);
                changed = true;
                break;
            }
        }
        if (changed) rebuildGroups();
    }

    function rebuildGroups() {
        let groupedMap = {};
        let newOrder = [];

        for (let i = 0; i < historyModel.count; i++) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;

            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }

            if (!groupedMap[gKey]) {
                groupedMap[gKey] = {
                    groupKey: gKey,
                    displayName: resolved.displayName,
                    icon: resolved.icon,
                    members: [],
                    count: 0,
                    unreadCount: 0,
                    latestSummary: nData.summary,
                    latestBody: nData.body,
                    latestTimestamp: nData.timestamp || Date.now()
                };
                newOrder.push(gKey);
            }

            let ts = nData.timestamp || Date.now();
            if (ts >= groupedMap[gKey].latestTimestamp) {
                groupedMap[gKey].latestTimestamp = ts;
                groupedMap[gKey].latestSummary = nData.summary;
                groupedMap[gKey].latestBody = nData.body;
            }

            groupedMap[gKey].members.push({
                "appName": nData.appName,
                "summary": nData.summary,
                "body": nData.body,
                "iconPath": nData.iconPath,
                "image": nData.image,
                "imagePath": nData.imagePath,
                "actionsJson": nData.actionsJson,
                "hasActions": nData.hasActions,
                "uid": nData.uid,
                "notif": nData.notif,
                "timestamp": ts,
                "urgency": nData.urgency,
                "read": nData.read
            });
            groupedMap[gKey].count = groupedMap[gKey].members.length;
            if (!nData.read) {
                groupedMap[gKey].unreadCount++;
            }
        }

        for (let i = groupedHistoryModel.count - 1; i >= 0; i--) {
            let item = groupedHistoryModel.get(i);
            if (!item || !groupedMap[item.groupKey]) {
                groupedHistoryModel.remove(i, 1);
            }
        }

        for (let i = 0; i < newOrder.length; i++) {
            let gKey = newOrder[i];
            let gData = groupedMap[gKey];
            let itemsJsonStr = JSON.stringify(gData.members);

            let existingIndex = -1;
            for (let j = 0; j < groupedHistoryModel.count; j++) {
                let item = groupedHistoryModel.get(j);
                if (item && item.groupKey === gKey) {
                    existingIndex = j;
                    break;
                }
            }

            let modelEntry = {
                "groupKey": gKey,
                "displayName": gData.displayName,
                "icon": gData.icon,
                "count": gData.count,
                "unreadCount": gData.unreadCount,
                "latestSummary": gData.latestSummary,
                "latestBody": gData.latestBody,
                "latestTimestamp": gData.latestTimestamp,
                "itemsJson": itemsJsonStr
            };

            if (existingIndex === -1) {
                groupedHistoryModel.insert(i, modelEntry);
            } else {
                if (existingIndex !== i && existingIndex < groupedHistoryModel.count && i < groupedHistoryModel.count) {
                    groupedHistoryModel.move(existingIndex, i, 1);
                }
                let item = groupedHistoryModel.get(i);
                if (item) {
                    if (item.displayName !== modelEntry.displayName) item.displayName = modelEntry.displayName;
                    if (item.icon !== modelEntry.icon) item.icon = modelEntry.icon;
                    if (item.count !== modelEntry.count) item.count = modelEntry.count;
                    if (item.unreadCount !== modelEntry.unreadCount) item.unreadCount = modelEntry.unreadCount;
                    if (item.latestSummary !== modelEntry.latestSummary) item.latestSummary = modelEntry.latestSummary;
                    if (item.latestBody !== modelEntry.latestBody) item.latestBody = modelEntry.latestBody;
                    if (item.latestTimestamp !== modelEntry.latestTimestamp) item.latestTimestamp = modelEntry.latestTimestamp;
                    if (item.itemsJson !== modelEntry.itemsJson) item.itemsJson = modelEntry.itemsJson;
                }
            }
        }
    }

    function clearNotifications(): void {
        Notifs.clearAll();
        root._isBatchUpdating = true;
        historyModel.clear();
        popupsModel.clear();
        groupedHistoryModel.clear();
        root.liveNotifs = {};
        root._isBatchUpdating = false;
    }

    function dismissNotification(uid) {
        let n = root.liveNotifs[uid];
        if (n && typeof n.dismiss === "function") n.dismiss();
        delete root.liveNotifs[uid];
        for (let i = 0; i < historyModel.count; i++) {
            let item = historyModel.get(i);
            if (item && item.uid === uid) {
                historyModel.remove(i, 1);
                break;
            }
        }
    }

    function dismissGroup(groupKey) {
        if (!historyModel || historyModel.count === 0) return;
        root._isBatchUpdating = true;
        for (let i = historyModel.count - 1; i >= 0; i--) {
            let nData = historyModel.get(i);
            if (!nData) continue;
            let n = nData.notif;
            let resolved = resolveApp(n || nData);
            let gKey = resolved.groupKey;

            if (nData.urgency === 2) {
                gKey += "_crit_" + nData.uid;
            }

            if (gKey === groupKey) {
                delete root.liveNotifs[nData.uid];
                if (n && typeof n.dismiss === "function") n.dismiss();
                if (i < historyModel.count) {
                    historyModel.remove(i, 1);
                }
            }
        }
        root._isBatchUpdating = false;
        rebuildGroups();
    }

    function removePopup(uid) {
        if (!popupsModel || popupsModel.count === 0) return;
        for (let i = popupsModel.count - 1; i >= 0; i--) {
            let p = popupsModel.get(i);
            if (!p) continue;
            let matches = (p.uid === uid || p.latestUid === uid);
            if (!matches && p.uidsJson) {
                try {
                    let uList = JSON.parse(p.uidsJson);
                    if (Array.isArray(uList) && uList.indexOf(uid) !== -1) {
                        matches = true;
                    }
                } catch (e) {}
            }
            if (matches) {
                if (i < popupsModel.count) {
                    popupsModel.remove(i, 1);
                }
                break;
            }
        }
    }

    Connections {
        target: Notifs
        function onHistoryChanged() { root.requeue++; syncTimer.restart(); }
        function onPopupsChanged() { root.requeue++; syncTimer.restart(); }
        function onArrivalMsChanged() { root.requeue++; syncTimer.restart(); }
    }

    Component.onCompleted: root.sync()
}
