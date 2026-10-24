// iRiS: the frame family ported from iNiR — an island on any screen edge that
// grows into whatever you clicked, with morphing glass surfaces, bubbles, a
// dock, a studio and its own settings overlay. Ryoku loads a barstyle Scene
// once per monitor via Frame's Loader, so this Scene hosts the single panel
// system one time on the primary output; the family's own Variants fan its
// surfaces across every screen. The boot ladder mirrors the reference shell:
// panels wait for the config mirror, then the first frame, then the deferred
// tier, so the desktop comes up in the same order the family was built for.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import inir
import inir.modules.common
import inir.modules.iris
import inir.modules.iris.critical
import inir.services
import "../../../../services/lib/screens.js" as Screens

Item {
    id: scene

    // The screen, set by Frame's per-monitor Loader.
    property var modelData: null

    width: 0
    height: 0

    // Host the single panel system on exactly one Scene: the primary output,
    // the first entry of the shared deduped screen list (services/lib/
    // screens.js). Matching by name keeps exactly one host even when a
    // duplicate output announce briefly swaps the ShellScreen object.
    readonly property bool isPrimary: {
        const list = Screens.uniqueByName(Quickshell.screens)
        return list.length > 0 && !!scene.modelData
            && list[0].name === scene.modelData.name
    }

    Loader {
        active: scene.isPrimary
        sourceComponent: Component {
            Item {
                // The critical tier: the bar/island, the reservations surface.
                ShellIrisCriticalPanels {}

                // The deferred tier: side panels, popups, studio, settings,
                // OSD, session and Spotlight.
                Loader {
                    active: Config.ready && GlobalStates.deferredPanelsReady
                    sourceComponent: Component { ShellIrisPanelsImpl {} }
                }

                // The reference's boot ladder, re-driven whenever the shell
                // hot-reloads (singletons keep their one-shot state).
                Component.onCompleted: {
                    // GlobalActions owns the `globalActions` IPC target; it is a
                    // lazy singleton, so without this nudge the target stays
                    // unregistered until the palette first opens.
                    void GlobalActions.allActions
                    GlobalStates.shellEntryReady = false
                    GlobalStates.deferredPanelsReady = false
                    if (Config.ready)
                        entryTimer.restart()
                }

                Timer {
                    id: entryTimer
                    interval: Appearance.animationsEnabled ? 200 : 0
                    onTriggered: {
                        GlobalStates.shellEntryReady = true
                        deferredTimer.start()
                    }
                }

                Timer {
                    id: deferredTimer
                    interval: 500
                    onTriggered: GlobalStates.deferredPanelsReady = true
                }

                Connections {
                    target: Config
                    function onReadyChanged() {
                        if (Config.ready && !GlobalStates.shellEntryReady)
                            entryTimer.restart()
                    }
                }
            }
        }
    }
}
