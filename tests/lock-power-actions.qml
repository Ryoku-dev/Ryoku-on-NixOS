import QtQuick
import Quickshell
import "shim"
ShellRoot {
    SddmShim { id: shim }
    Component.onCompleted: {
        shim.sddm.reboot();
        shim.sddm.powerOff();
    }
    Timer {
        interval: 1500; running: true
        onTriggered: Qt.quit()
    }
}
