pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import ".."
import Quickshell
import stage.modules.common as StageCfg
import shell.services as Shell

/**
 * The ii dock's options tree.
 *
 * The `dock` subtree is generated from the stage's own dock section and reads
 * through DockStore: the shared keys (enable/position/height) mirror
 * shell.json's top-level dock object (what the Hub, the CLI and the stage
 * edit pages own), `pinnedApps` and `order` fall back to the shared pins,
 * and every other leaf lives beside them under `dock.ii`. Writes commit the
 * same way, so the daemon stays the sole writer and the designs stay in sync.
 *
 * Every other section the dock reads aliases onto the stage's options tree:
 * one physical store shared with the Stage Editor, exactly where the ported
 * pages already read and write.
 */
Singleton {
    id: root

    readonly property bool ready: StageCfg.Config.ready

    function saveOptionsNow() {
        // Leaves commit per-change through DockStore; nothing to flush.
    }

    function setNestedValue(key: string, value: var, strict: bool) {
        DockStore.commit(key, value);
    }

    readonly property QtObject options: QtObject {
        readonly property var ai: StageCfg.Config.options.ai
        readonly property var appStats: StageCfg.Config.options.appStats
        readonly property var appearance: StageCfg.Config.options.appearance
        readonly property var apps: StageCfg.Config.options.apps
        readonly property var audio: StageCfg.Config.options.audio
        readonly property var background: StageCfg.Config.options.background
        readonly property var bar: StageCfg.Config.options.bar
        readonly property var battery: StageCfg.Config.options.battery
        readonly property var bluetooth: StageCfg.Config.options.bluetooth
        readonly property var calendar: StageCfg.Config.options.calendar
        readonly property var clockApp: StageCfg.Config.options.clockApp
        readonly property var googleDrive: StageCfg.Config.options.googleDrive
        readonly property var notes: StageCfg.Config.options.notes
        readonly property var bluetoothDeviceImages: StageCfg.Config.options.bluetoothDeviceImages
        readonly property var contextMenu: StageCfg.Config.options.contextMenu
        readonly property var dictation: StageCfg.Config.options.dictation
        readonly property var dockToPanel: StageCfg.Config.options.dockToPanel
        readonly property var dynamicIsland: StageCfg.Config.options.dynamicIsland
        readonly property var hacks: StageCfg.Config.options.hacks
        readonly property var idle: StageCfg.Config.options.idle
        readonly property var interactions: StageCfg.Config.options.interactions
        readonly property var language: StageCfg.Config.options.language
        readonly property var launcher: StageCfg.Config.options.launcher
        readonly property var light: StageCfg.Config.options.light
        readonly property var liveDraw: StageCfg.Config.options.liveDraw
        readonly property var localsend: StageCfg.Config.options.localsend
        readonly property var lock: StageCfg.Config.options.lock
        readonly property var media: StageCfg.Config.options.media
        readonly property var modes: StageCfg.Config.options.modes
        readonly property var networking: StageCfg.Config.options.networking
        readonly property var notifications: StageCfg.Config.options.notifications
        readonly property var phone: Shell.Config.phone
        readonly property var policies: StageCfg.Config.options.policies
        readonly property var resources: StageCfg.Config.options.resources
        readonly property var screenRecord: StageCfg.Config.options.screenRecord
        readonly property var screenSnip: StageCfg.Config.options.screenSnip
        readonly property var screenTime: StageCfg.Config.options.screenTime
        readonly property var search: StageCfg.Config.options.search
        readonly property var sidebar: StageCfg.Config.options.sidebar
        readonly property var sounds: StageCfg.Config.options.sounds
        readonly property var tablet: StageCfg.Config.options.tablet
        readonly property var time: StageCfg.Config.options.time
        readonly property var todo: StageCfg.Config.options.todo
        readonly property var userProfile: StageCfg.Config.options.userProfile
        readonly property var wallpaperSelector: StageCfg.Config.options.wallpaperSelector

        readonly property QtObject dock: QtObject {
        property var appGroups: DockStore.pull("appGroups", [])
        onAppGroupsChanged: DockStore.commit("appGroups", appGroups)
        property bool blockHoverInFullscreen: DockStore.pull("blockHoverInFullscreen", true)
        onBlockHoverInFullscreenChanged: DockStore.commit("blockHoverInFullscreen", blockHoverInFullscreen)
        property bool dimInactiveIcons: DockStore.pull("dimInactiveIcons", false)
        onDimInactiveIconsChanged: DockStore.commit("dimInactiveIcons", dimInactiveIcons)
        property real dockRadius: DockStore.pull("dockRadius", -1)
        onDockRadiusChanged: DockStore.commit("dockRadius", dockRadius)
        property string dockStyle: DockStore.pull("dockStyle", "floating")
        onDockStyleChanged: DockStore.commit("dockStyle", dockStyle)
        property bool enable: DockStore.pull("enable", false)
        onEnableChanged: DockStore.commit("enable", enable)
        property bool enableAppGroups: DockStore.pull("enableAppGroups", true)
        onEnableAppGroupsChanged: DockStore.commit("enableAppGroups", enableAppGroups)
        property bool enableAppTooltip: DockStore.pull("enableAppTooltip", false)
        onEnableAppTooltipChanged: DockStore.commit("enableAppTooltip", enableAppTooltip)
        property bool enableLivePreviewWidget: DockStore.pull("enableLivePreviewWidget", false)
        onEnableLivePreviewWidgetChanged: DockStore.commit("enableLivePreviewWidget", enableLivePreviewWidget)
        property bool enableMagnification: DockStore.pull("enableMagnification", false)
        onEnableMagnificationChanged: DockStore.commit("enableMagnification", enableMagnification)
        property bool enableMediaWidget: DockStore.pull("enableMediaWidget", false)
        onEnableMediaWidgetChanged: DockStore.commit("enableMediaWidget", enableMediaWidget)
        property bool enablePreview: DockStore.pull("enablePreview", true)
        onEnablePreviewChanged: DockStore.commit("enablePreview", enablePreview)
        property bool enableShapeMask: DockStore.pull("enableShapeMask", true)
        onEnableShapeMaskChanged: DockStore.commit("enableShapeMask", enableShapeMask)
        property bool enableSportsWidget: DockStore.pull("enableSportsWidget", false)
        onEnableSportsWidgetChanged: DockStore.commit("enableSportsWidget", enableSportsWidget)
        property bool enableTasksWidget: DockStore.pull("enableTasksWidget", false)
        onEnableTasksWidgetChanged: DockStore.commit("enableTasksWidget", enableTasksWidget)
        property bool enableWeatherWidget: DockStore.pull("enableWeatherWidget", false)
        onEnableWeatherWidgetChanged: DockStore.commit("enableWeatherWidget", enableWeatherWidget)
        property bool enableWidgetStack: DockStore.pull("enableWidgetStack", false)
        onEnableWidgetStackChanged: DockStore.commit("enableWidgetStack", enableWidgetStack)
        property real height: DockStore.pull("height", 56)
        onHeightChanged: DockStore.commit("height", height)
        property real hoverRegionHeight: DockStore.pull("hoverRegionHeight", 2)
        onHoverRegionHeightChanged: DockStore.commit("hoverRegionHeight", hoverRegionHeight)
        property bool hoverToReveal: DockStore.pull("hoverToReveal", true)
        onHoverToRevealChanged: DockStore.commit("hoverToReveal", hoverToReveal)
        property real iconSpacing: DockStore.pull("iconSpacing", -1)
        onIconSpacingChanged: DockStore.commit("iconSpacing", iconSpacing)
        property var ignoredAppRegexes: DockStore.pull("ignoredAppRegexes", [])
        onIgnoredAppRegexesChanged: DockStore.commit("ignoredAppRegexes", ignoredAppRegexes)
        property real islandSpacing: DockStore.pull("islandSpacing", 8)
        onIslandSpacingChanged: DockStore.commit("islandSpacing", islandSpacing)
        property bool islandsStyle: DockStore.pull("islandsStyle", false)
        onIslandsStyleChanged: DockStore.commit("islandsStyle", islandsStyle)
        property bool isolateMonitors: DockStore.pull("isolateMonitors", false)
        onIsolateMonitorsChanged: DockStore.commit("isolateMonitors", isolateMonitors)
        property string launchAnimation: DockStore.pull("launchAnimation", "bounce")
        onLaunchAnimationChanged: DockStore.commit("launchAnimation", launchAnimation)
        property string livePreviewAppId: DockStore.pull("livePreviewAppId", "")
        onLivePreviewAppIdChanged: DockStore.commit("livePreviewAppId", livePreviewAppId)
        property string livePreviewCaptureMode: DockStore.pull("livePreviewCaptureMode", "visible")
        onLivePreviewCaptureModeChanged: DockStore.commit("livePreviewCaptureMode", livePreviewCaptureMode)
        property bool livePreviewFollowActiveWindow: DockStore.pull("livePreviewFollowActiveWindow", true)
        onLivePreviewFollowActiveWindowChanged: DockStore.commit("livePreviewFollowActiveWindow", livePreviewFollowActiveWindow)
        property bool livePreviewPaintCursor: DockStore.pull("livePreviewPaintCursor", false)
        onLivePreviewPaintCursorChanged: DockStore.commit("livePreviewPaintCursor", livePreviewPaintCursor)
        property int livePreviewSlots: DockStore.pull("livePreviewSlots", 2)
        onLivePreviewSlotsChanged: DockStore.commit("livePreviewSlots", livePreviewSlots)
        property bool lockReorder: DockStore.pull("lockReorder", false)
        onLockReorderChanged: DockStore.commit("lockReorder", lockReorder)
        property string magnificationCurve: DockStore.pull("magnificationCurve", "cosine")
        onMagnificationCurveChanged: DockStore.commit("magnificationCurve", magnificationCurve)
        property bool magnificationDynamicSpacing: DockStore.pull("magnificationDynamicSpacing", true)
        onMagnificationDynamicSpacingChanged: DockStore.commit("magnificationDynamicSpacing", magnificationDynamicSpacing)
        property real magnificationInfluenceRadius: DockStore.pull("magnificationInfluenceRadius", 2.35)
        onMagnificationInfluenceRadiusChanged: DockStore.commit("magnificationInfluenceRadius", magnificationInfluenceRadius)
        property string magnificationMotion: DockStore.pull("magnificationMotion", "balanced")
        onMagnificationMotionChanged: DockStore.commit("magnificationMotion", magnificationMotion)
        property real magnificationScale: DockStore.pull("magnificationScale", 1.5)
        onMagnificationScaleChanged: DockStore.commit("magnificationScale", magnificationScale)
        property var manualOrder: DockStore.pull("manualOrder", [])
        onManualOrderChanged: DockStore.commit("manualOrder", manualOrder)
        property string monitor: DockStore.pull("monitor", "")
        onMonitorChanged: DockStore.commit("monitor", monitor)
        property bool monochromeIcons: DockStore.pull("monochromeIcons", false)
        onMonochromeIconsChanged: DockStore.commit("monochromeIcons", monochromeIcons)
        property string notificationAnimation: DockStore.pull("notificationAnimation", "bounce")
        onNotificationAnimationChanged: DockStore.commit("notificationAnimation", notificationAnimation)
        property var order: DockStore.pull("order", ["pin", "app:org.kde.dolphin", "app:kitty", "runningApps", "media", "weather", "sports", "livePreview", "phone", "trash", "overview"])
        onOrderChanged: DockStore.commit("order", order)
        property var pinnedApps: DockStore.pull("pinnedApps", ["org.kde.dolphin", "kitty"])
        onPinnedAppsChanged: DockStore.commit("pinnedApps", pinnedApps)
        property var pinnedFiles: DockStore.pull("pinnedFiles", [])
        onPinnedFilesChanged: DockStore.commit("pinnedFiles", pinnedFiles)
        property bool pinnedOnStartup: DockStore.pull("pinnedOnStartup", false)
        onPinnedOnStartupChanged: DockStore.commit("pinnedOnStartup", pinnedOnStartup)
        property string position: DockStore.pull("position", "auto")
        onPositionChanged: DockStore.commit("position", position)
        property string shapeMask: DockStore.pull("shapeMask", "Circle")
        onShapeMaskChanged: DockStore.commit("shapeMask", shapeMask)
        property bool showDividers: DockStore.pull("showDividers", true)
        onShowDividersChanged: DockStore.commit("showDividers", showDividers)
        property bool showNotificationBadges: DockStore.pull("showNotificationBadges", true)
        onShowNotificationBadgesChanged: DockStore.commit("showNotificationBadges", showNotificationBadges)
        property bool showOnlyOnFocusedMonitor: DockStore.pull("showOnlyOnFocusedMonitor", false)
        onShowOnlyOnFocusedMonitorChanged: DockStore.commit("showOnlyOnFocusedMonitor", showOnlyOnFocusedMonitor)
        property bool showOverviewButton: DockStore.pull("showOverviewButton", true)
        onShowOverviewButtonChanged: DockStore.commit("showOverviewButton", showOverviewButton)
        property bool showPhoneButton: DockStore.pull("showPhoneButton", false)
        onShowPhoneButtonChanged: DockStore.commit("showPhoneButton", showPhoneButton)
        property bool showPinButton: DockStore.pull("showPinButton", true)
        onShowPinButtonChanged: DockStore.commit("showPinButton", showPinButton)
        property bool showTrashButton: DockStore.pull("showTrashButton", false)
        onShowTrashButtonChanged: DockStore.commit("showTrashButton", showTrashButton)
        property bool smartGrouping: DockStore.pull("smartGrouping", false)
        onSmartGroupingChanged: DockStore.commit("smartGrouping", smartGrouping)
        property bool switchPresetsOnScroll: DockStore.pull("switchPresetsOnScroll", true)
        onSwitchPresetsOnScrollChanged: DockStore.commit("switchPresetsOnScroll", switchPresetsOnScroll)
        property var utilityWidgets: DockStore.pull("utilityWidgets", [])
        onUtilityWidgetsChanged: DockStore.commit("utilityWidgets", utilityWidgets)
        property real widgetRadius: DockStore.pull("widgetRadius", -1)
        onWidgetRadiusChanged: DockStore.commit("widgetRadius", widgetRadius)
        property var widgetStackItems: DockStore.pull("widgetStackItems", ["media", "weather", "tasks"])
        onWidgetStackItemsChanged: DockStore.commit("widgetStackItems", widgetStackItems)
        property QtObject overviewButton: QtObject {
            property bool alwaysShowShape: DockStore.pull("overviewButton.alwaysShowShape", false)
            onAlwaysShowShapeChanged: DockStore.commit("overviewButton.alwaysShowShape", alwaysShowShape)
            property string iconFile: DockStore.pull("overviewButton.iconFile", "")
            onIconFileChanged: DockStore.commit("overviewButton.iconFile", iconFile)
            property bool iconTint: DockStore.pull("overviewButton.iconTint", true)
            onIconTintChanged: DockStore.commit("overviewButton.iconTint", iconTint)
            property string shape: DockStore.pull("overviewButton.shape", "SoftBurst")
            onShapeChanged: DockStore.commit("overviewButton.shape", shape)
            property string symbol: DockStore.pull("overviewButton.symbol", "")
            onSymbolChanged: DockStore.commit("overviewButton.symbol", symbol)
        }
        property QtObject utilities: QtObject {
            property QtObject aiUsage: QtObject {
                property string provider: DockStore.pull("utilities.aiUsage.provider", "claude")
                onProviderChanged: DockStore.commit("utilities.aiUsage.provider", provider)
                property string squareWindow: DockStore.pull("utilities.aiUsage.squareWindow", "long")
                onSquareWindowChanged: DockStore.commit("utilities.aiUsage.squareWindow", squareWindow)
            }
            property QtObject converter: QtObject {
                property string category: DockStore.pull("utilities.converter.category", "length")
                onCategoryChanged: DockStore.commit("utilities.converter.category", category)
                property string from: DockStore.pull("utilities.converter.from", "cm")
                onFromChanged: DockStore.commit("utilities.converter.from", from)
                property string to: DockStore.pull("utilities.converter.to", "in")
                onToChanged: DockStore.commit("utilities.converter.to", to)
            }
            property QtObject favorites: QtObject {
                property var sites: DockStore.pull("utilities.favorites.sites", [])
                onSitesChanged: DockStore.commit("utilities.favorites.sites", sites)
            }
            property QtObject files: QtObject {
                property string folder: DockStore.pull("utilities.files.folder", "")
                onFolderChanged: DockStore.commit("utilities.files.folder", folder)
            }
            property QtObject pomodoro: QtObject {
                property bool clickToggles: DockStore.pull("utilities.pomodoro.clickToggles", true)
                onClickTogglesChanged: DockStore.commit("utilities.pomodoro.clickToggles", clickToggles)
            }
            property QtObject screenshots: QtObject {
                property string folder: DockStore.pull("utilities.screenshots.folder", "")
                onFolderChanged: DockStore.commit("utilities.screenshots.folder", folder)
            }
            property QtObject search: QtObject {
                property bool background: DockStore.pull("utilities.search.background", true)
                onBackgroundChanged: DockStore.commit("utilities.search.background", background)
                property string squareShape: DockStore.pull("utilities.search.squareShape", "Cookie9Sided")
                onSquareShapeChanged: DockStore.commit("utilities.search.squareShape", squareShape)
            }
            property QtObject send: QtObject {
                property string backend: DockStore.pull("utilities.send.backend", "kdeconnect")
                onBackendChanged: DockStore.commit("utilities.send.backend", backend)
                property string kdeDevice: DockStore.pull("utilities.send.kdeDevice", "")
                onKdeDeviceChanged: DockStore.commit("utilities.send.kdeDevice", kdeDevice)
                property string localsendAlias: DockStore.pull("utilities.send.localsendAlias", "")
                onLocalsendAliasChanged: DockStore.commit("utilities.send.localsendAlias", localsendAlias)
                property string localsendIp: DockStore.pull("utilities.send.localsendIp", "")
                onLocalsendIpChanged: DockStore.commit("utilities.send.localsendIp", localsendIp)
            }
            property QtObject shelf: QtObject {
                property bool removeAfterDrag: DockStore.pull("utilities.shelf.removeAfterDrag", false)
                onRemoveAfterDragChanged: DockStore.commit("utilities.shelf.removeAfterDrag", removeAfterDrag)
            }
            property QtObject stopwatch: QtObject {
                property bool clickToggles: DockStore.pull("utilities.stopwatch.clickToggles", true)
                onClickTogglesChanged: DockStore.commit("utilities.stopwatch.clickToggles", clickToggles)
            }
            property QtObject timer: QtObject {
                property bool clickPauses: DockStore.pull("utilities.timer.clickPauses", true)
                onClickPausesChanged: DockStore.commit("utilities.timer.clickPauses", clickPauses)
                property var presets: DockStore.pull("utilities.timer.presets", [1, 5, 10, 25])
                onPresetsChanged: DockStore.commit("utilities.timer.presets", presets)
            }
            property QtObject tools: QtObject {
                property var shown: DockStore.pull("utilities.tools.shown", ["screenSnip", "screenRecord", "colorPicker", "wallpaper", "darkMode"])
                onShownChanged: DockStore.commit("utilities.tools.shown", shown)
            }
            property QtObject water: QtObject {
                property int glassMl: DockStore.pull("utilities.water.glassMl", 250)
                onGlassMlChanged: DockStore.commit("utilities.water.glassMl", glassMl)
            }
        }
        }
    }
}
