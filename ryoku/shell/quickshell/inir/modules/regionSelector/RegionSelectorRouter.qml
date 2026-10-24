pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import inir

// The `region` IPC target. ryoshot owns the region-selector front, so every verb
// here launches ryoshot (preselecting the matching tool) instead of opening an
// in-shell overlay. Kept as the stable IPC surface external callers already use.
Scope {
    id: root

    function screenshot(): void { GlobalStates.launchRegionCapture("") }
    function search(): void { GlobalStates.launchRegionCapture("search") }
    function ocr(): void { GlobalStates.launchRegionCapture("ocr") }
    function record(): void { GlobalStates.launchRegionCapture("record") }
    function menu(): void { GlobalStates.launchRegionCapture("") }

    IpcHandler {
        target: "region"
        function screenshot(): void { root.screenshot() }
        function search(): void { root.search() }
        function googleLens(): void { root.search() }
        function ocr(): void { root.ocr() }
        function record(): void { root.record() }
        function recordWithSound(): void { root.record() }
        function menu(): void { root.menu() }
        function dismiss(): void { Quickshell.execDetached(["pkill", "-x", "-f", "qs -c ryoshot"]) }
        function current(): string { return JSON.stringify({ delegated: "ryoshot" }) }
    }
}
