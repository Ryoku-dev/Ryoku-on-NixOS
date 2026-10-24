import QtQuick
import Quickshell
import inir

Item {
    LazyLoader {
        loading: GlobalStates.deferredPanelsReady
        activeAsync: GlobalStates.deferredPanelsReady
        source: "modules/iris/ShellIrisPanelsImpl.qml"
    }
}
