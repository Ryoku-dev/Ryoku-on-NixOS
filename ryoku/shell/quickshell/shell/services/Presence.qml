pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Whether anyone can see the desktop: the session is locked, or the idle policy
// powered the displays off. Samplers that only feed on-screen readouts pause
// while it is dark, so a desktop nobody can see changes nothing and draws
// nothing. Any fault reads as not dark, so a readout can only keep running.
Singleton {
    id: root

    property bool locked: false
    property bool displaysOff: false
    readonly property bool dark: root.locked || root.displaysOff
    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"

    function clear() {
        root.locked = false;
        root.displaysOff = false;
    }

    function apply(line) {
        try {
            const frame = JSON.parse(line);
            if (typeof frame.locked !== "boolean" || typeof frame.displaysOff !== "boolean") {
                root.clear();
                return;
            }
            root.locked = frame.locked;
            root.displaysOff = frame.displaysOff;
        } catch (e) {
            root.clear();
        }
    }

    Socket {
        id: sub
        path: root.sockPath
        parser: SplitParser { onRead: line => root.apply(line) }
        Component.onCompleted: connected = true
        onConnectionStateChanged: {
            if (connected) {
                write("subscribe presence\n");
                flush();
            } else {
                root.clear();
                retry.restart();
            }
        }
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: if (!sub.connected) sub.connected = true
    }
}
