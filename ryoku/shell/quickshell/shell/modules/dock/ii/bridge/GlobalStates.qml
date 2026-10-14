pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import stage as Stage
import shell.services
import Ryoku.Ui.Singletons

/**
 * The ii dock's window to the shell's global state.
 *
 * The port reads one flat `GlobalStates` object; Ryoku splits it between the
 * Stage Editor's states (edit mode, sidebars, overview, the clock app's open
 * flag) and the dock's own session facts (what is dragging, ringing, or
 * mirrored right now). This singleton forwards everything the stage owns and
 * keeps the rest, so the dock never learns that the split exists.
 */
Singleton {
    id: root

    // ── forwarded from the Stage Editor ──────────────────────────────────────
    readonly property bool editMode: Stage.GlobalStates.editMode
    readonly property real editProgress: Stage.GlobalStates.editProgress
    readonly property bool screenLocked: Stage.GlobalStates.screenLocked
    readonly property bool lockLookActive: Stage.GlobalStates.lockLookActive
    readonly property bool presetBarHidden: Stage.GlobalStates.presetBarHidden
    readonly property bool barOpen: Stage.GlobalStates.barOpen
    readonly property bool overviewOpen: Stage.GlobalStates.overviewOpen
    property bool mediaControlsOpen: Stage.GlobalStates.mediaControlsOpen
    onMediaControlsOpenChanged: if (Stage.GlobalStates.mediaControlsOpen !== root.mediaControlsOpen)
        Stage.GlobalStates.mediaControlsOpen = root.mediaControlsOpen
    // The wallpaper tile flips this flag to ask for Ryoku's picker
    // (ryogami's full-screen browser); rising launches it.
    property bool wallpaperSelectorOpen: false
    onWallpaperSelectorOpenChanged: if (root.wallpaperSelectorOpen)
        Quickshell.execDetached(["ryogami", "wallpaper", "ui"]);
    readonly property bool editBarMenuOpen: Stage.GlobalStates.editBarMenuOpen
    readonly property bool editWidgetMenuOpen: Stage.GlobalStates.editWidgetMenuOpen
    property bool modesOpen: Stage.GlobalStates.modesOpen
    onModesOpenChanged: if (Stage.GlobalStates.modesOpen !== root.modesOpen)
        Stage.GlobalStates.modesOpen = root.modesOpen
    readonly property bool phoneCameraRunning: Stage.GlobalStates.phoneCameraRunning
    readonly property bool phoneMicRunning: Stage.GlobalStates.phoneMicRunning
    property bool clockAppOpen: Stage.GlobalStates.clockAppOpen
    onClockAppOpenChanged: if (Stage.GlobalStates.clockAppOpen !== root.clockAppOpen)
        Stage.GlobalStates.clockAppOpen = root.clockAppOpen
    property bool oskOpen: Stage.GlobalStates.oskOpen
    onOskOpenChanged: if (Stage.GlobalStates.oskOpen !== root.oskOpen)
        Stage.GlobalStates.oskOpen = root.oskOpen

    readonly property bool effectiveLeftOpen: Stage.GlobalStates.sidebarLeftOpen
    readonly property bool effectiveRightOpen: Stage.GlobalStates.sidebarRightOpen
    readonly property bool overviewSurfaceOpen: Stage.GlobalStates.overviewOpen

    function closeEditBarMenu() { Stage.GlobalStates.closeEditBarMenu(); }
    function closeEditWidgetMenu() { Stage.GlobalStates.closeEditWidgetMenu(); }
    function closeDesktopMenu() { Stage.GlobalStates.closeDesktopMenu(); }
    function openDesktopMenu(screenName, x, y, origin) { Stage.GlobalStates.openDesktopMenu(screenName, x, y, origin ?? "desktop"); }
    function openEditCatalogue(section, screenName, page) { Stage.GlobalStates.openEditCatalogue(section, screenName ?? "", page ?? ""); }
    function editHistoryPush(entry) { Stage.GlobalStates.editHistoryPush(entry); }
    function toggleOverview(monitorName) { Stage.GlobalStates.toggleOverview(monitorName); }
    function launchColorPicker() { Stage.GlobalStates.launchColorPicker(); }
    // The dock's settings pages live in this port: opening one mounts the
    // settings host over the desktop with the requested page.
    property bool settingsOpen: false
    property string settingsPage: "dock"
    property string settingsSubPage: ""
    function openSettingsPage(pageId, subPageId, sectionId) {
        root.settingsPage = String(pageId ?? "dock");
        root.settingsSubPage = String(subPageId ?? "");
        root.settingsOpen = true;
    }
    function closeSettingsPage() {
        root.settingsOpen = false;
        root.settingsSubPage = "";
    }
    function setDockInset(screenName, side, thickness, reserved) {
        Stage.GlobalStates.setDockInset(screenName, side, thickness);
        const next = Object.assign({}, root.dockInsets);
        next[screenName] = { side: side, thickness: thickness, reserved: reserved ?? false };
        root.dockInsets = next;
    }

    // ── the dock's own session state ─────────────────────────────────────────
    property var dockInsets: ({})
    property var barIslands: ({})
    property bool fileDragActive: false
    property bool alarmRinging: false
    property bool islandOwnsAlarm: false
    property var oledSaverMonitors: []
    property string clockAppPendingTab: ""
    property string reminderToOpen: ""
    property bool localSendPopupOpen: false
    property var localSendPopupTransfer: null
    property int liveDrawSaveRequest: 0
    property color colorPickerPopupColor: "#00000000"
    property var dockContents: []

    function registerDockContent(content) {
        const list = root.dockContents.slice();
        if (list.indexOf(content) < 0)
            list.push(content);
        root.dockContents = list;
    }

    function unregisterDockContent(content) {
        root.dockContents = root.dockContents.filter(c => c !== content);
    }

    // The dock's clock tile: open the clock app, optionally landing on a tab.
    function openClockApp(tab) {
        root.clockAppPendingTab = String(tab ?? "");
        root.clockAppOpen = true;
    }

    // The search tile opens Ryoku's launcher.
    function toggleSearchOnly(screenName) {
        ShellState.requestSurfaceActive("launcher", screenName ?? "");
    }

    // The dock has no media-mode screen concept; media is a widget, not a mode.
    function isMediaModeActiveForScreen(screenName): bool {
        return false;
    }

    // The overview backdrop controller belongs to the stage's overview; the
    // dock only asks for it to keep its own reveal quiet while it is open.
    function overviewBackgroundControllerFor(screenName) {
        return null;
    }

    // The clock app's timetable deep link: open the shell's left sidebar.
    function openTimetableAt(day) {
        ShellState.requestSurfaceActive("sidebar-left", "");
    }
}
