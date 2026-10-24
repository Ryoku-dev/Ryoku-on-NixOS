pragma Singleton

import QtQuick
import Quickshell
import inir.services

// Compatibility alias: the frame's niri-facing consumers talk to the one
// compositor seam adapter. Names and shapes follow the reference service so
// the vendored UI stays untouched; the data is the window-manager seam's, so
// every action resolves on whichever compositor is running.
Singleton {
    id: root

    readonly property var outputs: CompositorService.outputs
    readonly property var displayScales: CompositorService.displayScales
    readonly property var workspaces: CompositorService.workspaces
    readonly property var allWorkspaces: CompositorService.allWorkspaces
    readonly property var focusedWorkspaceIndex: CompositorService.focusedWorkspaceIndex
    readonly property var focusedWorkspaceId: CompositorService.focusedWorkspaceId
    readonly property var currentOutputWorkspaces: CompositorService.currentOutputWorkspaces
    readonly property var currentOutput: CompositorService.currentOutput
    readonly property var windows: CompositorService.windows
    readonly property var liveWindows: CompositorService.liveWindows
    readonly property var activeWindow: CompositorService.activeWindow
    readonly property var actionReady: CompositorService.actionReady

    readonly property bool inOverview: CompositorService.overviewOpen
    readonly property bool nativeOverview: CompositorService.nativeOverview
    property bool configLoaded: true
    property bool configLoadFailed: false
    property string configError: ""
    property bool overviewHotCornersReady: false
    property var overviewHotCornersByOutput: ({})
    property var overviewHotCornersGlobal: []
    property var overviewHotCornerOverrides: ({})
    readonly property bool singleWindowFullWidthEnabled: false

    signal configLoadFinished(bool ok, string error)
    signal windowOrderChanged
    signal windowUrgentChanged

    function switchToWorkspaceById(id) {
        CompositorService.switchToWorkspaceById(id);
    }

    function focusWindow(id) {
        CompositorService.focusWindow(id);
    }

    function closeWindow(id) {
        CompositorService.closeWindow(id);
    }

    function moveWindowToWorkspaceById(id, workspaceId) {
        CompositorService.moveWindowToWorkspaceById(id, workspaceId);
    }

    function toggleOverview() {
        CompositorService.toggleOverview();
    }

    function switchToWorkspaceIndex(index) {
        CompositorService.switchToWorkspaceIndex(index);
    }

    function hasWindowsOnActiveWorkspace(outputName: string): bool {
        return CompositorService.hasWindowsOnActiveWorkspace(outputName);
    }

    function activeWorkspaceCovers(outputName) {
        return CompositorService.activeWorkspaceCovers(outputName);
    }

    function tilingWindowCount(id) {
        return CompositorService.tilingWindowCount(id);
    }

    function filterCurrentWorkspace(toplevels, screen) {
        return CompositorService.filterCurrentWorkspace(toplevels, screen);
    }

    readonly property var currentLayout: CompositorService.currentLayout
    readonly property var keyboardLayoutNames: CompositorService.keyboardLayoutNames
    readonly property int currentKeyboardLayoutIndex: CompositorService.currentKeyboardLayoutIndex
    readonly property bool hasMultipleKeyboardLayouts: CompositorService.hasMultipleKeyboardLayouts

    function getCurrentKeyboardLayoutName() {
        return CompositorService.getCurrentKeyboardLayoutName();
    }

    function switchLayout(name) {
        CompositorService.switchLayout(name);
    }

    function switchLayoutPrevious() {
        CompositorService.switchLayoutPrevious();
    }

    function applyLayout(workspaceId, name) {
        CompositorService.applyLayout(workspaceId, name);
    }

    function sortToplevels() {
        CompositorService.sortToplevels();
    }

    function maximizeColumn() {
    }

    function powerOffMonitors() {
        CompositorService.powerOffMonitors();
    }

    function powerOnMonitors() {
        CompositorService.powerOnMonitors();
    }

    function quit() {
    }

    function refreshOverviewHotCorners() {
    }

    function overviewHotCornersForOutput(outputName) {
        return CompositorService.overviewHotCornersForOutput(outputName);
    }

    function isOverviewHotCornerActive(outputName, cornerName) {
        return CompositorService.isOverviewHotCornerActive(outputName, cornerName);
    }
}
