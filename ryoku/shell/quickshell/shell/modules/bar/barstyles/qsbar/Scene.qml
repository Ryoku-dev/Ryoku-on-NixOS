// QS Bar (Quickshell Rise) entry, adapted to Ryoku's barstyle contract.
//
// Ryoku loads a barstyle Scene once per monitor via Frame's Loader, so this
// Scene hosts the single bar system a single time on the primary output. The
// VariantRoot inside fans one bar across every screen itself, so multi-monitor
// behaviour is unchanged.
//
// There is a single qsbar now: no V1/V2 variants, no runtime switch. The bar
// form (islands · full · fit · dock · notch) is a Theme property, not a
// separate implementation. IpcRouter owns the external IPC surface.

import Quickshell
import QtQuick
import "../../../../services/lib/screens.js" as Screens
import "."
import "core"

Item {
    id: sceneRoot

    // The screen, set by Frame's per-monitor Loader.
    property var modelData: null

    width: 0
    height: 0

    // Host the single shell system on exactly one Scene: the primary output, the
    // first entry of the shared deduped screen list (services/lib/screens.js).
    // Matching by name (not object identity) keeps exactly one Scene primary even
    // when a duplicate output announce briefly swaps the ShellScreen object, so
    // the bar system is never hosted twice.
    readonly property bool isPrimary: {
        var list = Screens.uniqueByName(Quickshell.screens)
        return list.length > 0 && !!sceneRoot.modelData
            && list[0].name === sceneRoot.modelData.name
    }

    Loader {
        active: sceneRoot.isPrimary
        sourceComponent: Component {
            Item {
                VariantRoot {
                    id: barRoot
                }

                IpcRouter {
                    barRoot: barRoot
                }
            }
        }
    }
}
