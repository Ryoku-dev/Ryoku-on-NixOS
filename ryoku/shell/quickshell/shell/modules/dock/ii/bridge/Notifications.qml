pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services as RyokuNotifs
import ".."

/**
 * The ii dock's notification view.
 *
 * The reference ran its own notification store: a flat `list` of entries, a
 * `notify` signal the badges watch, and `publishInternalNotification` for
 * the reminders, todo and transfer alerts the clock app raises. Ryoku owns
 * the real server and the popup UI, so this forwards the reference's shape
 * onto it: `list` wraps the shell's tracked history, `notify` fires when a
 * notification arrives, and internal publishes go out through the desktop
 * notification API. A publish with actions keeps a waiting `notify-send`
 * alive so the chosen action comes back as `internalActionInvoked`, exactly
 * the signal the reminders service listens on.
 */
Singleton {
    id: root

    signal notify(notification: var)
    signal internalActionInvoked(identifier: string, notificationId: var, payload: var)

    // Everything the reference reads: the shell's tracked history in the
    // entry shape the badges, the progress scanner and the clock app expect.
    readonly property var list: (RyokuNotifs.Notifs.history ?? []).map(n => root.wrap(n))

    // Our publish ids -> { dbusId, payload }, so discard can close the real
    // notification and the waiting sender can report which one it belongs to.
    property var _sent: ({})
    property int _nextId: 1

    function wrap(n) {
        return {
            "notificationId": n.id,
            "notification": n,
            "internal": false,
            "appName": n.appName ?? "",
            "appIcon": n.appIcon ?? "",
            "summary": n.summary ?? "",
            "body": n.body ?? "",
            "urgency": String(n.urgency ?? "normal"),
            "time": root._arrivalOf(n.id),
            "actions": [],
            "customActions": [],
            "internalActionPayload": ({})
        };
    }

    function _arrivalOf(id) {
        const a = RyokuNotifs.Notifs.arrivalMs ?? ({});
        return a[id] ?? 0;
    }

    function publishInternalNotification(options: var): var {
        const notificationId = root._nextId++;
        const appName = String(options?.appName ?? "Ryoku");
        const summary = String(options?.summary ?? "");
        const body = String(options?.body ?? "");
        const urgency = String(options?.urgency ?? "normal");
        const actions = Array.from(options?.actions ?? [])
            .filter(action => String(action?.text ?? "").length > 0);
        const payload = options?.actionPayload ?? ({});
        const expire = Number(options?.expireTimeout ?? -1);

        const args = ["notify-send", "-a", appName, "--urgency",
            urgency === "critical" ? "critical" : urgency === "low" ? "low" : "normal"];
        const icon = String(options?.appIcon ?? "");
        if (icon.length > 0)
            args.push("-i", icon);
        if (expire > 0)
            args.push("--expire-time", String(expire));
        for (let i = 0; i < actions.length; i++)
            args.push("--action", String(actions[i].identifier ?? ("action" + i)) + "=" + actions[i].text);
        args.push(summary, body);

        if (actions.length === 0) {
            Quickshell.execDetached(args);
            return notificationId;
        }

        // Actions need the reply: --print-id names the notification and the
        // process waits for the close, printing the chosen action.
        const proc = actionSender.createObject(root, { "args": args, "ourId": notificationId, "payload": payload });
        proc.start();
        return notificationId;
    }

    function discardNotification(id) {
        const sent = root._sent[id];
        if (sent && sent.dbusId !== undefined)
            Quickshell.execDetached(["notify-send", "--close", String(sent.dbusId)]);
    }

    Component {
        id: actionSender

        Process {
            id: sender

            required property var args
            required property var ourId
            required property var payload
            property var dbusId: undefined
            command: ["notify-send", "--print-id"].concat(args.slice(1))
            stdout: StdioCollector { id: senderOut }

            onExited: () => {
                const lines = senderOut.text.split("\n").filter(l => l.length > 0);
                const dbusId = lines.length > 0 ? lines[0] : "";
                const action = lines.length > 1 ? lines[1] : "";
                const book = Object.assign({}, root._sent);
                delete book[ourId];
                root._sent = book;
                if (action.startsWith("__qs_"))
                    root.internalActionInvoked(action, ourId, payload);
            }

            onRunningChanged: {
                if (running) {
                    const book = Object.assign({}, root._sent);
                    book[ourId] = { "dbusId": undefined, "payload": payload };
                    root._sent = book;
                }
            }
        }
    }

    // A real arrival must fire `notify` the way the reference's server did:
    // watch the shell's popup stack and report entries never seen before.
    property var _seen: ({})

    function _emitArrivals() {
        const popups = RyokuNotifs.Notifs.popups ?? [];
        const fresh = [];
        const seen = Object.assign({}, root._seen);
        for (let i = 0; i < popups.length; i++) {
            const n = popups[i];
            if (n && seen[n.id] === undefined) {
                seen[n.id] = true;
                fresh.push(root.wrap(n));
            }
        }
        root._seen = seen;
        for (let i = 0; i < fresh.length; i++)
            root.notify(fresh[i]);
    }

    Connections {
        target: RyokuNotifs.Notifs
        function onPopupsChanged() {
            root._emitArrivals();
        }
    }
}
