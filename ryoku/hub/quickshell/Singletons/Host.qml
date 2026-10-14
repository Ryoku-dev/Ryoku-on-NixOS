pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool ready: false
    property string packageManager: ""
    property string init: ""
    property var snapshots: ({ "supported": false, "reason": "" })
    property var aur: ({ "supported": false, "reason": "" })

    function capability(name) {
        if (name === "snapshots")
            return root.snapshots;
        if (name === "aur")
            return root.aur;
        return null;
    }

    function supports(name) {
        var cap = root.capability(name);
        return root.ready && cap !== null && cap.supported === true;
    }

    function reason(name) {
        var cap = root.capability(name);
        return cap && cap.reason ? String(cap.reason) : "";
    }

    Process {
        command: ["ryoku-host", "capabilities"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var value = JSON.parse(text);
                    root.packageManager = String(value.packageManager || "");
                    root.init = String(value.init || "");
                    root.snapshots = value.snapshots || ({ "supported": false, "reason": "" });
                    root.aur = value.aur || ({ "supported": false, "reason": "" });
                    root.ready = root.packageManager !== "" && root.init !== "";
                } catch (e) {
                    root.ready = false;
                }
            }
        }
    }
}
