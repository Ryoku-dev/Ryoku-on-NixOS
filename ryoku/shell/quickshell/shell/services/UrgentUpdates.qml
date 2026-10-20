pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons
import "UrgentUpdatePolicy.js" as Policy

// The urgent-update alert. When the branch this box follows carries a commit a
// maintainer marked `Urgent:` and the box does not run it yet (`urgent` in the
// daemon's updates frame, docs/nixos.md, "Urgent updates"), it raises a
// critical notification that stays up, comes through Do Not Disturb
// (Notifs.isUrgentUpdate) and starts the update from its button. Closing it
// snoozes it for Policy.remindAfterMs; it is gone once the update lands. One
// alert per QML engine.
Singleton {
    id: svc

    readonly property bool enabled: Config.urgentUpdates?.enabled ?? true
    readonly property var alerts: Updates.urgent
    property var shown: ({})
    property string pending: ""

    function evaluate() {
        svc.shown = Policy.prune(svc.shown, svc.alerts);
        if (svc.alerts.length === 0 || !svc.enabled) {
            svc.closeOpen();
            return;
        }
        if (notifier.running)
            return;
        var alert = Policy.due(svc.alerts, svc.shown, Date.now(), svc.enabled);
        if (!alert)
            return;
        svc.pending = alert.commit;
        notifier.command = ["notify-send", "--app-name=Ryoku", "--icon=software-update-urgent",
            "--urgency=critical", "--expire-time=0", "--hint=boolean:x-ryoku-urgent-update:true",
            "--action=update=" + I18n.tr("Update now"), "--action=later=" + I18n.tr("Later"), "--wait",
            I18n.tr("Update Ryoku now"), svc.body()];
        notifier.running = true;
    }

    function body() {
        var lines = Policy.reasons(svc.alerts, 3);
        var more = svc.alerts.length - lines.length;
        if (more > 0)
            lines.push(I18n.tr("and %1 more urgent fixes").arg(more));
        return lines.join("\n");
    }

    // The box took the update (or the switch went off) while the alert was up.
    function closeOpen() {
        var open = Notifs.tracked || [];
        for (var i = 0; i < open.length; i++)
            if (Notifs.isUrgentUpdate(open[i]))
                Notifs.dismiss(open[i]);
    }

    function finish(choice) {
        var pending = svc.pending;
        svc.pending = "";
        if (svc.alerts.some(a => a.commit === pending)) {
            var next = Object.assign({}, svc.shown);
            next[pending] = Date.now();
            svc.shown = next;
        }
        if (choice === "update") {
            // The run reports to Ryoku Settings, which opens on its Updates
            // page to show it and ask for the password.
            Quickshell.execDetached(["ryoku", "update", "--gui"]);
            Quickshell.execDetached(["ryoku-shell", "hub", "open", "updates"]);
        }
    }

    onAlertsChanged: soon.restart()
    onEnabledChanged: soon.restart()
    Component.onCompleted: soon.restart()
    Timer { id: soon; interval: 300; onTriggered: svc.evaluate() }
    // Brings a snoozed alert back while the update still waits.
    Timer {
        interval: 10 * 60 * 1000
        running: svc.enabled && svc.alerts.length > 0
        repeat: true
        onTriggered: svc.evaluate()
    }
    Process {
        id: notifier
        stdout: StdioCollector {
            onStreamFinished: svc.finish(this.text.trim())
        }
    }
}
