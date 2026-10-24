pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import stage.modules.common as StagePersist

/**
 * The ii dock's persistent state.
 *
 * One store with the Stage Editor: the dock's groups (alarms, timer,
 * clipboard, sidebar, dockUtilities, phone) all live in the stage's states
 * tree, so a value written from the dock reads back the same in the editor's
 * panels and one file holds the shell's whole non-config state.
 */
Singleton {
    id: root

    readonly property bool ready: StagePersist.Persistent.ready
    readonly property var states: StagePersist.Persistent.states
}
