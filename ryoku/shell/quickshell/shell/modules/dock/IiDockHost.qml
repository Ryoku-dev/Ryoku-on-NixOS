pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services
import "ii" as Ii
import "ii/utilities/DockUtilityCatalog.js" as DockUtilityCatalog

/**
 * The ii dock design's global host.
 *
 * The port's Dock.qml is a Scope: it repeats itself across the screens it is
 * told to cover, so this host mounts it once for the whole session, gated on
 * the shared store selecting the "ii" design. The same gate owns the rest of
 * the design's bundle: the live-draw overlay per screen, the alarm ringing
 * popup and the clock app window. Its settings are the Stage Editor's dock
 * pages, which reach the design's stateful services through `actions`.
 */
Scope {
    id: root

    readonly property bool active: Dock.design === "ii" && Dock.cfg("enabled", false)

    // What the Stage Editor's dock pages cannot do through the shared store:
    // the saved layouts, the folders and the utility tiles, which the
    // design's own services and catalogue keep in step with its order. Built
    // only while the design is up, so another design never instantiates this
    // one's services.
    LazyLoader {
        id: actions
        active: root.active

        QtObject {
            readonly property var presets: Ii.DockPresets.presetsList ?? []
            readonly property int activePreset: {
                Ii.Config.options.dock.pinnedApps;
                Ii.Config.options.dock.order;
                Ii.Config.options.dock.enableMediaWidget;
                Ii.Config.options.dock.enableWeatherWidget;
                Ii.Config.options.dock.enableSportsWidget;
                Ii.Config.options.dock.enableLivePreviewWidget;
                Ii.DockPresets.presetsList;
                return Ii.DockPresets.findMatchingPresetIndex();
            }
            function applyPreset(index: int): void {
                const preset = Ii.DockPresets.presetsList[index];
                if (preset)
                    Ii.DockPresets.applyPreset(preset);
            }
            function savePreset(name: string): void {
                Ii.DockPresets.saveCurrentAsPreset(name);
            }
            function deletePreset(index: int): void {
                Ii.DockPresets.deletePreset(index);
            }
            function addFolder(path: string): void {
                Ii.TaskbarApps.addPinnedFile(path);
            }
            function removeFolder(path: string): void {
                Ii.TaskbarApps.removePinnedFile(path);
            }
            function moveFolder(from: int, to: int): void {
                Ii.TaskbarApps.reorderPinnedFileByIndex(from, to);
            }
            readonly property var utilityGroups: DockUtilityCatalog.groups
            readonly property var utilityKinds: DockUtilityCatalog.kinds
            readonly property var utilities: DockUtilityCatalog.normalize(Ii.Config.options.dock.utilityWidgets ?? [])
            function setUtility(kind: string, on: bool): void {
                const current = Ii.Config.options.dock.utilityWidgets ?? [];
                Dock.setDesignCfg("ii", "utilityWidgets", on
                    ? DockUtilityCatalog.withKind(current, kind, false)
                    : DockUtilityCatalog.withoutKind(current, kind));
            }
        }
    }

    Binding {
        target: Dock
        property: "designActions"
        value: actions.item
    }

    Loader {
        active: root.active
        asynchronous: true
        sourceComponent: Component {
            Ii.Dock {}
        }
    }

    // Live draw: one window per screen, mounted while the feature is on.
    Repeater {
        model: root.active ? Quickshell.screens : []

        delegate: Loader {
            required property var modelData
            active: Ii.LiveDraw.enabled
            sourceComponent: Component {
                Ii.LiveDrawWindow {
                }
            }
            onLoaded: if (item)
                item.screen = modelData
        }
    }

    Loader {
        active: root.active
        sourceComponent: Component {
            Ii.AlarmRingingPopup {}
        }
    }

    Loader {
        active: root.active
        asynchronous: true
        sourceComponent: Component {
            Ii.ClockAppWindow {}
        }
    }
}
