pragma Singleton
pragma ComponentBehavior: Bound

import inir.modules.common.functions
import inir.services
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import inir.modules.common

// Vendored iRiS path contract, retargeted into Ryoku's storage. The family
// keeps its per-feature state, themes and caches under the Ryoku namespaces
// instead of the upstream ones. Wallpaper, recording and screenshot are owned
// by Ryoku's own services, so nothing here points at an upstream script tree.
Singleton {
    id: root

    // XDG Dirs, with "file://"
    readonly property string home: StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
    readonly property string config: StandardPaths.standardLocations(StandardPaths.ConfigLocation)[0]
    readonly property string state: StandardPaths.standardLocations(StandardPaths.StateLocation)[0]
    readonly property string cache: StandardPaths.standardLocations(StandardPaths.CacheLocation)[0]
    readonly property string genericCache: StandardPaths.standardLocations(StandardPaths.GenericCacheLocation)[0]
    readonly property string documents: StandardPaths.standardLocations(StandardPaths.DocumentsLocation)[0]
    readonly property string downloads: StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0]
    readonly property string pictures: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
    readonly property string music: StandardPaths.standardLocations(StandardPaths.MusicLocation)[0]
    readonly property string videos: StandardPaths.standardLocations(StandardPaths.MoviesLocation)[0]
    readonly property string homePath: FileUtils.trimFileProtocol(home)
    readonly property string configPath: FileUtils.trimFileProtocol(config)
    readonly property string statePath: FileUtils.trimFileProtocol(state)
    readonly property string cachePath: FileUtils.trimFileProtocol(cache)
    readonly property string genericCachePath: FileUtils.trimFileProtocol(genericCache)
    readonly property string documentsPath: FileUtils.trimFileProtocol(documents)
    readonly property string downloadsPath: FileUtils.trimFileProtocol(downloads)
    readonly property string picturesPath: FileUtils.trimFileProtocol(pictures)
    readonly property string musicPath: FileUtils.trimFileProtocol(music)
    readonly property string videosPath: FileUtils.trimFileProtocol(videos)

    // Vendored payload: the assets, scripts, translations and defaults that
    // ship at the root of this config component, two levels above this file.
    readonly property string modulePath: FileUtils.trimFileProtocol(Qt.resolvedUrl("../.."))
    function payloadPath(sub: string): string {
        return `${root.modulePath}/${sub}`
    }
    property string assetsPath: root.payloadPath("assets")
    property string scriptPath: root.payloadPath("scripts")
    property string scriptsPath: FileUtils.trimFileProtocol(scriptPath)

    // Family state lives under ryoku/inir, never under the upstream names.
    property string stateUserPath: `${root.statePath}/ryoku/inir`
    property string wallpapersPath: `${root.picturesPath}/Wallpapers`
    property string screenshotsPath: `${root.picturesPath}/Screenshots`
    property string persistentStatesPath: `${root.stateUserPath}/states.json`
    property string eventsPath: `${root.stateUserPath}/events.json`
    property string weatherCachePath: `${root.stateUserPath}/weather-cache.json`
    property string screenTimePath: `${root.stateUserPath}/screentime`
    property string favicons: `${root.cachePath}/ryoku/inir/media/favicons`
    // User avatar paths
    property string userAvatarPathAccountsService: FileUtils.trimFileProtocol(`/var/lib/AccountsService/icons/${SystemInfo.username}`)
    property string userAvatarPathRicersAndWeirdSystems: `${root.homePath}/.face`
    property string userAvatarPathRicersAndWeirdSystems2: `${root.homePath}/.face.icon`
    property int userAvatarRevision: 0
    readonly property var userAvatarPaths: [
        userAvatarPathAccountsService,
        userAvatarPathRicersAndWeirdSystems,
        userAvatarPathRicersAndWeirdSystems2
    ].filter(path => String(path ?? "").trim().length > 0)
    readonly property string userAvatarSourcePrimary: avatarSourceAt(0)

    FileView {
        path: root.userAvatarPathAccountsService
        watchChanges: true
        // Most accounts never set an avatar; a missing file is the common case.
        printErrors: false
        onFileChanged: root.userAvatarRevision++
    }
    property string coverArt: `${root.cachePath}/ryoku/inir/media/coverart`
    // The live wallpaper palette the daemon publishes; the family's theme
    // loader reads this M3 role file exactly as it read the generated one.
    property string generatedMaterialThemePath: `${root.cachePath}/ryoku/colors.json`
    property string tempImages: "/tmp/ryoku-inir/media/images"
    property string booruPreviews: `${root.cachePath}/ryoku/inir/media/boorus`
    property string booruDownloads: `${root.wallpapersPath}`
    property string booruDownloadsNsfw: `${root.wallpapersPath}/nsfw`
    property string latexOutput: `${root.cachePath}/ryoku/inir/media/latex`
    property string shellConfig: `${root.configPath}/ryoku/inir`
    property string shellConfigName: "iris.json"
    property string shellConfigPath: `${root.shellConfig}/${root.shellConfigName}`
    property string todoPath: `${root.stateUserPath}/todo.json`
    property string todoTxtPath: `${root.stateUserPath}/todo.txt`
    property string notepadPath: `${root.stateUserPath}/notepad.txt`
    property string notesPath: `${root.stateUserPath}/notes.txt`
    property string notificationsPath: `${root.stateUserPath}/notifications.json`
    property string calendarSyncCachePath: `${root.stateUserPath}/calendar-sync-cache.json`
    property string screenshotTemp: "/tmp/ryoku-inir/media/screenshot"
    // Ryoku-owned surfaces; the family routes through its services, not scripts.
    property string wallpaperSwitchScriptPath: ""
    property string userActions: FileUtils.trimFileProtocol(`${root.shellConfig}/actions`)

    function shortHomePath(path: string): string {
        const cleaned = FileUtils.trimFileProtocol(path)
        if (cleaned === root.homePath)
            return "~"
        if (cleaned.startsWith(root.homePath + "/"))
            return "~" + cleaned.slice(root.homePath.length)
        return cleaned
    }

    function avatarSourceAt(index: int): string {
        if (index < 0 || index >= userAvatarPaths.length)
            return ""

        const path = String(userAvatarPaths[index] ?? "").trim()
        return path.length > 0 ? `file://${path}?ryoku-inir-avatar=${root.userAvatarRevision}` : ""
    }

    function nextAvatarSource(currentSource: string): string {
        const normalized = String(currentSource ?? "")
            .replace(/^file:\/\//, "")
            .replace(/\?ryoku-inir-avatar=\d+$/, "")

        for (let i = 0; i < root.userAvatarPaths.length; ++i) {
            if (String(root.userAvatarPaths[i] ?? "") === normalized)
                return avatarSourceAt(i + 1)
        }

        return root.userAvatarSourcePrimary
    }
    // Cleanup on init
    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", `${root.shellConfig}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.stateUserPath}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.favicons}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.coverArt}`])
        Quickshell.execDetached(["rm", "-rf", `${root.booruPreviews}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.booruPreviews}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.latexOutput}`])
        Quickshell.execDetached(["rm", "-rf", `${root.tempImages}`])
        Quickshell.execDetached(["mkdir", "-p", `${root.tempImages}`])
    }
}
