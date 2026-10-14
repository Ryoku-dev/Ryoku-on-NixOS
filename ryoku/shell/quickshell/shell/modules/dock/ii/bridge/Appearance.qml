pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import ".."
import Quickshell
import stage.modules.common as Stage

/**
 * The ii dock's design tokens.
 *
 * Everything forwards to the shell-wide Stage Appearance (palette, rounding,
 * font, animation curves), so the dock matches the bar and the widgets. The
 * one exception is `sizes.dockButtonSize`: the reference derives it from the
 * dock's own height option, which lives in the shared dock store, so the
 * sizes group is wrapped to add that token.
 */
Singleton {
    id: root

    readonly property QtObject m3colors: Stage.Appearance.m3colors
    readonly property QtObject colors: Stage.Appearance.colors
    readonly property QtObject rounding: Stage.Appearance.rounding
    readonly property QtObject font: Stage.Appearance.font
    readonly property QtObject animationCurves: Stage.Appearance.animationCurves
    readonly property QtObject animation: Stage.Appearance.animation
    readonly property real animMultiplier: Stage.Appearance.animMultiplier
    readonly property bool reducedMotion: Stage.Appearance.reducedMotion

    readonly property QtObject sizes: QtObject {
        property int dockButtonSize: Math.round((Config.options.dock.height ?? 60) * 0.85)

        readonly property real minimumTouchTarget: Stage.Appearance.sizes.minimumTouchTarget
        readonly property real space1: Stage.Appearance.sizes.space1
        readonly property real space2: Stage.Appearance.sizes.space2
        readonly property real space3: Stage.Appearance.sizes.space3
        readonly property real space4: Stage.Appearance.sizes.space4
        readonly property real space5: Stage.Appearance.sizes.space5
        readonly property real space6: Stage.Appearance.sizes.space6
        readonly property real controlHeight: Stage.Appearance.sizes.controlHeight
        readonly property real familyWidgetGridStep: Stage.Appearance.sizes.familyWidgetGridStep
        readonly property real widgetGridStep: Stage.Appearance.sizes.widgetGridStep
        readonly property real baseBarHeight: Stage.Appearance.sizes.baseBarHeight
        readonly property real barHeight: Stage.Appearance.sizes.barHeight
        readonly property real barReferenceHeight: Stage.Appearance.sizes.barReferenceHeight
        readonly property real barReferenceWidth: Stage.Appearance.sizes.barReferenceWidth
        readonly property real barContentScale: Stage.Appearance.sizes.barContentScale
        readonly property real verticalBarContentScale: Stage.Appearance.sizes.verticalBarContentScale
        readonly property real barCenterSideModuleWidth: Stage.Appearance.sizes.barCenterSideModuleWidth
        readonly property real barCenterSideModuleWidthShortened: Stage.Appearance.sizes.barCenterSideModuleWidthShortened
        readonly property real barCenterSideModuleWidthHellaShortened: Stage.Appearance.sizes.barCenterSideModuleWidthHellaShortened
        readonly property real barShortenScreenWidthThreshold: Stage.Appearance.sizes.barShortenScreenWidthThreshold
        readonly property real barHellaShortenScreenWidthThreshold: Stage.Appearance.sizes.barHellaShortenScreenWidthThreshold
        readonly property real elevationMargin: Stage.Appearance.sizes.elevationMargin
        readonly property real toolbarHeight: Stage.Appearance.sizes.toolbarHeight
        readonly property real editModeMargin: Stage.Appearance.sizes.editModeMargin
        readonly property real editModeEdgeMargin: Stage.Appearance.sizes.editModeEdgeMargin
        readonly property real editModeDrawerWidth: Stage.Appearance.sizes.editModeDrawerWidth
        readonly property real fabShadowRadius: Stage.Appearance.sizes.fabShadowRadius
        readonly property real fabHoveredShadowRadius: Stage.Appearance.sizes.fabHoveredShadowRadius
        readonly property real hyprlandGapsOut: Stage.Appearance.sizes.hyprlandGapsOut
        readonly property real mediaControlsWidth: Stage.Appearance.sizes.mediaControlsWidth
        readonly property real mediaControlsHeight: Stage.Appearance.sizes.mediaControlsHeight
        readonly property real notificationPopupWidth: Stage.Appearance.sizes.notificationPopupWidth
        readonly property real osdWidth: Stage.Appearance.sizes.osdWidth
        readonly property real searchWidthCollapsed: Stage.Appearance.sizes.searchWidthCollapsed
        readonly property real searchWidth: Stage.Appearance.sizes.searchWidth
        readonly property real sidebarWidth: Stage.Appearance.sizes.sidebarWidth
        readonly property real sidebarWidthExtended: Stage.Appearance.sizes.sidebarWidthExtended
        readonly property real baseVerticalBarWidth: Stage.Appearance.sizes.baseVerticalBarWidth
        readonly property real verticalBarWidth: Stage.Appearance.sizes.verticalBarWidth
        readonly property real verticalBarWindowWidth: Stage.Appearance.sizes.verticalBarWindowWidth
        readonly property real wallpaperSelectorWidth: Stage.Appearance.sizes.wallpaperSelectorWidth
        readonly property real wallpaperSelectorHeight: Stage.Appearance.sizes.wallpaperSelectorHeight
        readonly property real wallpaperSelectorSidebarWidth: Stage.Appearance.sizes.wallpaperSelectorSidebarWidth
        readonly property real wallpaperSelectorSidebarButtonHeight: Stage.Appearance.sizes.wallpaperSelectorSidebarButtonHeight
        readonly property real wallpaperSelectorSidebarHorizontalPadding: Stage.Appearance.sizes.wallpaperSelectorSidebarHorizontalPadding
        readonly property real wallpaperSelectorSidebarButtonSpacing: Stage.Appearance.sizes.wallpaperSelectorSidebarButtonSpacing
        readonly property real wallpaperSelectorSidebarGroupSpacing: Stage.Appearance.sizes.wallpaperSelectorSidebarGroupSpacing
        readonly property real wallpaperSelectorSearchWidth: Stage.Appearance.sizes.wallpaperSelectorSearchWidth
        readonly property real wallpaperSelectorSortDialogWidth: Stage.Appearance.sizes.wallpaperSelectorSortDialogWidth
        readonly property real wallpaperSelectorItemMargins: Stage.Appearance.sizes.wallpaperSelectorItemMargins
        readonly property real wallpaperSelectorItemPadding: Stage.Appearance.sizes.wallpaperSelectorItemPadding
    }
}
