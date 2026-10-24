pragma Singleton
import Quickshell
Singleton { id: root
    readonly property bool active: false
    readonly property var ethernet: null
    readonly property bool wifiEnabled: false
    readonly property var wifiStatus: null
}
