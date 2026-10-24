pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    property bool inhibit: false
    property bool timed: false
    property int extendBy: 0
    property real extendMinutes: 0
    function formatMinutes(value: real): string { return "" }
    function toggleInhibit(value: bool) {}
}
