pragma Singleton
import QtQuick
import Quickshell
import shell.services
import "../../"

// Ryoku seam: the serpantinum self-updater is gone -- Ryoku ships signed
// packages and `ryoku update` is the one update path. This keeps the badge
// shape the guide and the about page read (localVersion / remoteVersion /
// updateAvailable) fed from the shell daemon's update frame instead.
Item {
    id: root

    property bool isChecking: false
    property string localVersion: Updates.installed || "..."
    property string remoteVersion: Updates.latest || ""
    readonly property bool updateAvailable: Updates.pending > 0
    property string lastNotifiedVersion: ""

    function checkUpdate() {
        Updates.check();
    }

    Connections {
        target: Updates
        function onPendingChanged() { root.framePulse++; }
    }
    property int framePulse: 0

    // keep the version strings fresh when the daemon's frame lands
    Connections {
        target: Updates
        function onFrameChanged() {
            root.localVersion = Updates.installed || "...";
            root.remoteVersion = Updates.latest || "";
        }
    }
}
