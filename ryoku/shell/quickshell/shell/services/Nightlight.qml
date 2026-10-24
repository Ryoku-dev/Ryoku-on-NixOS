pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// QML view of the daemon `nightlight` topic. The backend's state lives in
// ryoku-shell (nightlight.go), so QML never pgreps or shells out to
// ryoku-cmd-nightlight for state: `subscribe nightlight` streams
// {on, temperature, schedule} on every change, and `call nightlight.toggle` /
// `nightlight.set` send the intent back. The daemon publishes an off frame at
// startup, so the tile is never blank before the first event.
Singleton {
    id: root

    property bool on: false
    property int temperature: 4000
    // "sun" follows sunset to sunrise where the user is; "clock" follows the
    // hours the user set; "off" is manual only.
    property string schedule: "off"

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"

    function toggle() {
        root.call("nightlight.toggle", {});
    }

    function setEnabled(on, temperature) {
        root.call("nightlight.set", {
            on: on === true,
            temperature: typeof temperature === "number" ? temperature : 0
        });
    }

    // Same semantics as the Hub's Displays page: warmth applies live while the
    // light is on and is kept for the next switch-on otherwise (nightlight.set
    // with on:false only turns it off). Optimistic; the frame confirms it.
    function setTemperature(kelvin) {
        root.temperature = kelvin;
        if (root.on)
            root.setEnabled(true, kelvin);
    }

    function setSchedule(sun) {
        root.schedule = sun ? "sun" : "off";
        root.call("nightlight.set", { schedule: root.schedule });
    }

    function apply(line) {
        try {
            const f = JSON.parse(line);
            root.on = f.on === true;
            if (typeof f.temperature === "number" && f.temperature > 0)
                root.temperature = f.temperature;
            if (f.schedule === "off" || f.schedule === "sun" || f.schedule === "clock")
                root.schedule = f.schedule;
        } catch (e) {
            // A malformed frame keeps the last good state.
        }
    }

    function call(method, args) {
        ctl.queued += "call " + method + " " + JSON.stringify(args) + "\n";
        if (ctl.connected)
            ctl.flushQueued();
        else
            ctl.connected = true;
    }

    Socket {
        id: sub
        path: root.sockPath
        parser: SplitParser { onRead: line => root.apply(line) }
        Component.onCompleted: connected = true
        onConnectionStateChanged: {
            if (connected) {
                write("subscribe nightlight\n");
                flush();
            } else {
                retry.restart();
            }
        }
    }

    // The daemon may be down when the shell loads (or restart under it); retry
    // quietly so the view repopulates once it returns.
    Timer {
        id: retry
        interval: 2000
        onTriggered: if (!sub.connected) sub.connected = true
    }

    Socket {
        id: ctl
        path: root.sockPath
        property string queued: ""

        function flushQueued() {
            if (queued.length === 0)
                return;
            write(queued);
            flush();
            queued = "";
        }

        onConnectionStateChanged: if (connected) flushQueued()
    }
}
