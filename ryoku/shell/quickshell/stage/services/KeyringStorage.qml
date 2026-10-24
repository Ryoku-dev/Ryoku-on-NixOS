pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    property var keyringData: null
    property bool loaded: false
}
