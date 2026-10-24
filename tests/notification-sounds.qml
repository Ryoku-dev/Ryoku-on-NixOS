import QtQuick
import Quickshell
import Quickshell.Io
import shell.services as Shell
import stage.services as Stage
import stage.modules.common as StageCommon

// Runs the shell's notification server beside the Stage one, as the desktop
// does, against shims for paplay and ryoku-shell
// (tests/notification-sounds.sh), and reads back what each was asked to play.
ShellRoot {
    id: root

    property int phase: 0
    property int waited: 0
    property int seen: 0
    readonly property var sounds: StageCommon.Config.options.sounds
    // Read both services while the config loads: a NotificationServer created
    // after that misses Quickshell's reload hook and never goes live.
    readonly property int stageCount: Stage.Notifications.list.length
    readonly property int shellCount: Shell.Notifs.popups.length

    FileView {
        id: calls
        path: Quickshell.env("RYOKU_TEST_CALLS")
        printErrors: false
    }

    // The plays logged since the last check.
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

    function publish(urgency): void {
        Stage.Notifications.publishInternalNotification({
            appName: "Reminder",
            summary: "Stretch",
            urgency: urgency,
            sound: true
        });
    }

    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: {
            root.waited++;
            if (root.waited > 60) {
                console.log("FAIL: timed out in phase " + root.phase);
                Qt.quit();
                return;
            }
            switch (root.phase) {
            case 0:
                if (!StageCommon.Config.ready)
                    return;
                Quickshell.execDetached(["notify-send", "-a", "Mail", "New mail", "From the test"]);
                root.phase = 1;
                return;
            case 1:
                if (!Stage.Notifications.list.some(n => n.summary === "New mail")
                        || !Shell.Notifs.popups.some(n => n.summary === "New mail"))
                    return;
                root.phase = 2;
                return;
            case 2: {
                // The Stage config may post its own notice on a first start, so
                // count the chimes against what the shell put up.
                const chimes = root.lines();
                const shown = Shell.Notifs.popups.length;
                root.expect(chimes.length === shown && chimes.every(line => line === "ryoku-shell sound notification"),
                    "each of the " + shown + " notifications chimes once, through the Hub cue: "
                    + JSON.stringify(chimes));
                root.publish("critical");
                root.publish("normal");
                root.phase = 3;
                return;
            }
            case 3: {
                const cues = root.lines();
                root.expect(JSON.stringify(cues) === JSON.stringify([
                        "ryoku-shell sound notification-critical",
                        "ryoku-shell sound notification"]),
                    "a Stage notification plays the Hub cue for its urgency: " + JSON.stringify(cues));
                root.sounds.notifications = false;
                root.publish("normal");
                root.sounds.notifications = true;
                root.sounds.enable = false;
                root.publish("normal");
                root.sounds.enable = true;
                root.sounds.neverPlayApps = ["Reminder"];
                root.publish("normal");
                root.sounds.neverPlayApps = [];
                root.phase = 4;
                return;
            }
            case 4: {
                const muted = root.lines();
                root.expect(muted.length === 0,
                    "the Stage switches still silence it: " + JSON.stringify(muted));
                Qt.quit();
                return;
            }
            }
        }
    }
}
