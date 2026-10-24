pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    function overlayOntoDefaults(obj: var): var { return obj }
    function reconcile() {}
    function syncFromConfig() {}
}
