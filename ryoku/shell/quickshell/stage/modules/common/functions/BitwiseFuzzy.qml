pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root
    function prepare(value: var) {}
    function search(value: var, query: var): var { return [] }
}
