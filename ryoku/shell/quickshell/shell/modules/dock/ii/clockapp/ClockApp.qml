pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import stage.services
import Ryoku.Ui.Singletons
import ".."


/**
 * The clock app: its lifecycle and its ways in.
 *
 * Only this Scope lives with the shell — a keybind and an IPC target. The window is the
 * same RetainedLoader Usage and Modes use: built asynchronously when the clock opens, so
 * the keybind never waits on the tree, and kept hidden for 30 s after it closes, so a
 * quick reopen is instant. When that window expires the tree is destroyed and collected:
 * a closed clock holds no tree, no timers and no cache. Alarms, timers and the pomodoro
 * keep running in their services, exactly as they do for the bar and the sidebar.
 */
Scope {
    id: root

    readonly property var tabIds: ["alarms", "worldClock", "timer", "stopwatch", "pomodoro", "bedtime", "reminders"]
    function focusExistingWindow(): void {
        const title = Translation.tr("Clock");
        const windows = Wm.windows ?? [];
        for (let i = 0; i < windows.length; i++) {
            const window = windows[i];
            if (String(window?.title ?? "") === title) {
                Wm.focusWindow(window.id);
                return;
            }
        }
    }

    function requestOpen(tab = ""): void {
        GlobalStates.clockAppPendingTab = root.tabIds.includes(tab) ? tab : "";
        if (GlobalStates.clockAppOpen) {
            root.focusExistingWindow();
            return;
        }
        GlobalStates.clockAppOpen = true;
    }

    function requestClose(): void {
        GlobalStates.clockAppOpen = false;
    }

    function requestToggle(): void {
        if (GlobalStates.clockAppOpen)
            root.requestClose();
        else
            root.requestOpen();
    }

    RetainedLoader {
        id: windowLoader
        requested: GlobalStates.clockAppOpen
        // The last clock stays warm for a quick reopen, then goes entirely.
        retainFor: 30000
        sourceComponent: ClockAppWindow {
            onCloseRequested: root.requestClose()
        }
    }

    GlobalShortcut {
        name: "clockToggle"
        description: Translation.tr("Toggles the clock app")
        onPressed: root.requestToggle()
    }

    GlobalShortcut {
        name: "clockOpen"
        description: Translation.tr("Opens the clock app")
        onPressed: root.requestOpen()
    }

    GlobalShortcut {
        name: "clockClose"
        description: Translation.tr("Closes the clock app")
        onPressed: root.requestClose()
    }

    IpcHandler {
        target: "clock"

        function open(): void {
            root.requestOpen();
        }

        function close(): void {
            root.requestClose();
        }

        function toggle(): void {
            root.requestToggle();
        }

        /// alarms | worldClock | timer | stopwatch | pomodoro | bedtime
        function openTab(tab: string): void {
            root.requestOpen(String(tab ?? ""));
        }
    }
}
