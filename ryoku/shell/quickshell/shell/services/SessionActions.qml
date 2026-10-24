pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Fires the session actions the Controls bar's hold buttons complete. Lock and
// sleep are the daemon's own verbs, the same `ryoku-shell lock` the Super+L
// keybind runs on every compositor and the `ryoku-shell suspend` the lid uses:
// a fail-closed lock, then logind. Logout, reboot and shutdown are the
// `session.*` calls the daemon registers (session.go); QML never spawns
// systemctl itself, keeping the state-in-daemon / render-in-QML split. All are
// fire-and-forget: a lock or sleep answers through the compositor, and reboot
// and shutdown tear the session down, so no reply is awaited. Contract 13 sec 8.
Singleton {
    id: root

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-shell.sock"

    // action is one of "lock" | "suspend" | "logout" | "reboot" | "shutdown".
    function run(action) {
        if (action === "lock" || action === "suspend") {
            Quickshell.execDetached(["ryoku-shell", action]);
            return;
        }
        ctl.queued += "call session." + action + " {}\n";
        if (ctl.connected)
            ctl.flushQueued();
        else
            ctl.connected = true;
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
