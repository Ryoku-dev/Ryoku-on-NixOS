pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import stage.modules.common as StageDirs

/**
 * The ii dock's paths.
 *
 * The stage's own path service is extended with the handful of locations the
 * dock's services need (todo, reminders, sports cache, the recorder and the
 * localsend installer); everything shared reads through it. The dock's own
 * helpers (the localsend bridge, the browser and AI-usage scripts) live in
 * its vendored scripts directory, and its assets in its vendored assets
 * directory, so nothing depends on the upstream's install layout.
 */
Singleton {
    id: root

    readonly property string home: StageDirs.Directories.home
    readonly property string config: StageDirs.Directories.config
    readonly property string state: StageDirs.Directories.state
    readonly property string cache: StageDirs.Directories.cache
    readonly property string genericCache: StageDirs.Directories.genericCache
    readonly property string documents: StageDirs.Directories.documents
    readonly property string pictures: StageDirs.Directories.pictures
    readonly property string videos: StageDirs.Directories.videos
    readonly property string downloads: String(StandardPaths.standardLocations(StandardPaths.DownloadLocation)[0] || home + "/Downloads").replace(/^file:\/\//, "")
    readonly property string shellConfig: StageDirs.Directories.shellConfig
    readonly property string shellConfigPath: StageDirs.Directories.shellConfigPath

    // The dock's vendored helper tree and asset tree, inside the shell.
    readonly property string dockDir: Quickshell.shellPath("modules/dock/ii")
    readonly property string scriptPath: dockDir + "/scripts"
    readonly property string assetsPath: dockDir + "/assets"

    // Per-service state files under the shared state dir.
    readonly property string todoPath: state + "/ryoku/todo.json"
    readonly property string todoDoneHistoryPath: state + "/ryoku/todo_done.json"
    readonly property string remindersPath: state + "/ryoku/reminders.json"
    readonly property string reminderAttachmentsDir: state + "/ryoku/reminder_attachments"
    readonly property string appStats: state + "/ryoku/app_stats"
    readonly property string sportsCachePath: state + "/ryoku/generated/sports.json"
    readonly property string coverArt: cache + "/ryoku/media/coverart"
    readonly property string screenshotTemp: `/tmp/quickshell-${root.username}/media/screenshot`
    readonly property string localSendDownloadPath: downloads + "/localsend"

    // Ryoku's recorder CLI: same verbs the tile uses (bare toggle,
    // --fullscreen, --region, --pause); it drives GPU Screen Recorder.
    readonly property string recordScriptPath: "ryoku-cmd-record"
    readonly property string wallpaperSwitchScriptPath: StageDirs.Directories.wallpaperSwitchScriptPath

    readonly property string username: Quickshell.env("USER") || ""
}
