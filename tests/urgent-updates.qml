import QtQuick
import Quickshell
import Quickshell.Io
import shell.services as Shell

// Runs the shell's notification server and the urgent-update alert against
// shims for ryoku and ryoku-shell (tests/urgent-updates.sh). The updates frame
// is set here, as the daemon would publish it.
ShellRoot {
    id: root

    property int phase: 0
    property int waited: 0
    property int seen: 0
    property var card: null
    // Read the services while the config loads: a NotificationServer created
    // after that misses Quickshell's reload hook and never goes live.
    readonly property int popupCount: Shell.Notifs.popups.length
    readonly property bool alertsOn: Shell.UrgentUpdates.enabled

    FileView {
        id: calls
        path: Quickshell.env("RYOKU_TEST_CALLS")
        printErrors: false
    }

    // The shim calls logged since the last check.
    function lines(): var {
        calls.reload();
        calls.waitForJob();
        const all = calls.text().split("\n").filter(line => line.length > 0);
        const fresh = all.slice(root.seen);
        root.seen = all.length;
        return fresh;
    }

    function expect(cond, message): void {
        console.log((cond ? "PASS: " : "FAIL: ") + message);
    }

    function alert(): var {
        return Shell.Notifs.popups.find(n => Shell.Notifs.isUrgentUpdate(n)) ?? null;
    }

    function urgent(list): void {
        Shell.Updates.frame = { available: list.length > 0, urgent: list };
    }

    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: {
            root.waited++;
            if (root.waited > 80) {
                console.log("FAIL: timed out in phase " + root.phase);
                Qt.quit();
                return;
            }
            switch (root.phase) {
            case 0:
                if (!root.alertsOn)
                    return;
                Shell.Notifs.dnd = true;
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "Mail", "Critical mail", "under DND"]);
                root.urgent([{ commit: "aaaaaaa", subject: "[global] lock: fix", reason: "the lock screen opened without a password" }]);
                root.phase = 1;
                return;
            case 1: {
                const n = root.alert();
                if (!n)
                    return;
                root.expect(n.appName === "Ryoku" && n.expireTimeout === 0,
                    "the alert comes from Ryoku and stays up: " + n.appName + " " + n.expireTimeout);
                root.expect(n.body.indexOf("the lock screen opened without a password") >= 0,
                    "the alert names the reason: " + JSON.stringify(n.body));
                root.expect(!Shell.Notifs.popups.some(p => p.summary === "Critical mail"),
                    "Do Not Disturb still holds back every other popup");
                const ids = n.actions.map(a => a.identifier + "=" + a.text).join(",");
                root.expect(ids === "update=Update now,later=Later", "the alert offers Update now and Later: " + ids);
                const comp = Qt.createComponent(Quickshell.env("RYOKU_CARD"));
                root.card = comp.createObject(root, { notif: n, compact: true });
                root.expect(root.card && root.card.expanded && root.card.visibleActions.length === 2,
                    "its popup opens with both buttons showing" + (comp.errorString() ? ": " + comp.errorString() : ""));
                root.card?.destroy();
                n.actions.find(a => a.identifier === "update").invoke();
                root.phase = 2;
                return;
            }
            case 2: {
                const ran = root.lines();
                if (ran.length < 3)
                    return;
                root.expect(JSON.stringify(ran.sort()) === JSON.stringify(["ryoku update --gui", "ryoku-shell hub open updates", "ryoku-shell sound notification-critical"]),
                    "the alert chimes the urgent cue, and Update now starts the update and opens its page: " + JSON.stringify(ran));
                root.expect(Shell.UrgentUpdates.shown["aaaaaaa"] !== undefined, "the alert is snoozed once it closes");
                Shell.UrgentUpdates.evaluate();
                root.phase = 3;
                return;
            }
            case 3:
                root.expect(!root.alert(), "a snoozed alert stays away while the same commit waits");
                root.urgent([{ commit: "bbbbbbb", subject: "[ryoku] net: fix", reason: "" },
                             { commit: "aaaaaaa", subject: "[global] lock: fix", reason: "the lock screen opened without a password" }]);
                root.phase = 4;
                return;
            case 4: {
                const n = root.alert();
                if (!n)
                    return;
                root.expect(n.body.split("\n")[0] === "[ryoku] net: fix",
                    "a newer urgent commit alerts at once, its subject standing in for a reason: " + JSON.stringify(n.body));
                root.urgent([]);
                root.phase = 5;
                return;
            }
            case 5:
                if (root.alert())
                    return;
                root.expect(Object.keys(Shell.UrgentUpdates.shown).length === 0,
                    "once the update lands the alert closes and leaves no state");
                Qt.quit();
                return;
            }
        }
    }
}
