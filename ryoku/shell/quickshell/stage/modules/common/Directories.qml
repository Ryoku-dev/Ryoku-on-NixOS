pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtCore
import stage.modules.common.functions
// The Stage Editor's own paths. The reference resolved everything off a single
// illogical-impulse config directory; Ryoku keeps the editor's state under
// ~/.config/ryoku/stage so it never collides with the daemon-owned shell.json,
// and reads the shared XDG bases the rest of the desktop uses. The script and
// cache paths the copied services probe are pointed at the shell's installed
// tree (RYOKU_SHELL_DIR) or a state cache; a missing helper degrades to a no-op
// rather than a crash, exactly as in the reference.
Singleton {
    id: root

    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0] || ""
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0] || ""
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0] || ""
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0] || ""
    readonly property string genericCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0] || ""
    readonly property string coverArt: FileUtils.trimFileProtocol(`${root.cache}/ryoku/media/coverart`)
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.coverArt])
    readonly property string documents: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0] || ""
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0] || ""
    readonly property string videos: StandardPaths.standardLocations(StandardPaths.MoviesLocation)[0] || ""

    // The editor's config home and its store file (the widget-instance list).
    readonly property string shellConfig: FileUtils.trimFileProtocol(`${root.config}/ryoku/stage`)
    readonly property string shellConfigName: "stage-editor.json"
    readonly property string shellConfigPath: `${root.shellConfig}/${root.shellConfigName}`
    readonly property string localPreferencesName: "stage-editor.local.json"
    readonly property string localPreferencesPath: `${root.shellConfig}/${root.localPreferencesName}`

    // The shell's installed tree, for the helpers the copied services call.
    readonly property string _shellDir: Quickshell.env("RYOKU_SHELL_DIR")
    readonly property string assetsPath: Quickshell.shellPath("assets")
    readonly property string scriptPath: FileUtils.trimFileProtocol(
        root._shellDir && root._shellDir.length > 0
            ? `${root._shellDir}/scripts`
            : `${root.config}/quickshell/shell/scripts`)
    readonly property string stageScriptPath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../../scripts"))
    readonly property string iiAssetsPath: FileUtils.trimFileProtocol(Quickshell.shellPath("modules/dock/ii/assets"))

    // Wallpaper + theme caches the copied services write into.
    // Ryogami owns the wallpaper library and its generated 640×360 stills.
    readonly property string ryogamiConfigPath: FileUtils.trimFileProtocol(`${root.config}/ryoku/ryogami.json`)
    readonly property string ryogamiCachePath: FileUtils.trimFileProtocol(`${root.genericCache}/ryogami`)
    readonly property string stageVideoPosterCachePath: FileUtils.trimFileProtocol(`${root.cache}/stage/video-posters`)
    readonly property string colorCachePath: FileUtils.trimFileProtocol(`${root.cache}/stage/colors`)
    readonly property string generatedMaterialThemePath: FileUtils.trimFileProtocol(`${root.cache}/stage/theme.json`)
    readonly property string wallpaperPreviewColorsPath: FileUtils.trimFileProtocol(`${root.cache}/stage/wallpaper-preview-colors.json`)
    readonly property string defaultPreviewColorsDarkPath: FileUtils.trimFileProtocol(`${root.cache}/stage/preview-dark.json`)
    readonly property string defaultPreviewColorsLightPath: FileUtils.trimFileProtocol(`${root.cache}/stage/preview-light.json`)
    readonly property string lockscreenColorsPath: FileUtils.trimFileProtocol(`${root.cache}/stage/lockscreen-colors.json`)
    readonly property string generatedWallpaperCategoryPath: FileUtils.trimFileProtocol(`${root.cache}/stage/wallpaper-category.json`)
    readonly property string defaultWallpaperImagePath: ""
    readonly property string customThemes: FileUtils.trimFileProtocol(`${root.config}/ryoku/stage/themes`)
    readonly property string defaultThemes: FileUtils.trimFileProtocol(`${root.config}/ryoku/stage/themes`)
    readonly property string notificationsPath: FileUtils.trimFileProtocol(`${root.state}/stage/notifications.json`)
    readonly property string notesDir: FileUtils.trimFileProtocol(`${root.state}/stage/notes`)
    readonly property string notesPath: FileUtils.trimFileProtocol(`${root.state}/stage/notes.json`)
    readonly property string userWidgetsPath: FileUtils.trimFileProtocol(`${root.config}/ryoku/stage/widgets`)
    readonly property string userProfileImagePath: FileUtils.trimFileProtocol(`${root.state}/stage/user-profile.png`)
    readonly property string widgetExtensionsPath: FileUtils.trimFileProtocol(`${root.state}/stage/widget-extensions`)
    readonly property string widgetBackupsPath: FileUtils.trimFileProtocol(`${root.state}/stage/widget-backups`)
    readonly property string localSendDownloadPath: FileUtils.trimFileProtocol(`${root.state}/stage/localsend`)

    // Helpers the copied services shell out to. Ryoku ships its own wallpaper
    // switcher seam (ryoku-stage-wallpaper) and colour generator
    // (ryoku-stage-colors); they resolve to the shell tree's scripts when the
    // tree is present (a dev checkout) and to the bare name otherwise, which
    // the packaged box finds on PATH (where ryoku-shell installs ryoku-*).
    readonly property string wallpaperSwitchScriptPath: root._helper("ryoku-stage-wallpaper")
    readonly property string extractColorsScriptPath: root._helper("ryoku-stage-colors")
    readonly property string generateLockscreenColorsScriptPath: root._helper("ryoku-stage-colors")

    function _helper(name) {
        // The same resolution the plugin discover script uses: a dev checkout
        // runs the scripts straight out of the tree; a packaged box finds the
        // bare name on PATH, where ryoku-shell installs every ryoku-* script.
        return root._shellDir && root._shellDir.length > 0
            ? FileUtils.trimFileProtocol(`${root.scriptPath}/${name}`) : name;
    }
    readonly property string gammaControlScriptPath: ""
    readonly property string losslessCutDesktopPath: FileUtils.trimFileProtocol(`${root.home}/.local/share/applications/losslesscut.desktop`)
}
