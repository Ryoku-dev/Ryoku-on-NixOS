pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    property var applications: []
    function byId(value: string): var { return null }
    function heuristicLookup(value: string): var { return null }
}
