import QtQuick
import Ryoku.Ui.Singletons

FolioTabData {
    tabKey: "library"
    title: I18n.tr("Library")
    note: I18n.tr("Locations, thumbnails, caches, and recovery.")
    sections: [
        {
            title: I18n.tr("Folders"),
            subtitle: "",
            controls: [
                { id: "paths.wallpaper",
                  key: "paths.wallpaper",
                  kind: "text",
                  variant: "path",
                  label: I18n.tr("Wallpaper directory"),
                  help: I18n.tr("Folder Ryogami scans for image and video wallpapers."),
                  placeholder: I18n.tr("~/Pictures/Wallpapers"),
                  search: ["paths.wallpaper", "wallpaper", "directory", "text"] },
                { id: "paths.videoWallpaper",
                  key: "paths.videoWallpaper",
                  kind: "text",
                  variant: "path",
                  label: I18n.tr("Video directory"),
                  help: I18n.tr("Separate folder for video wallpapers. Defaults to the wallpaper directory."),
                  placeholder: I18n.tr("Same as wallpaper directory"),
                  search: ["paths.videoWallpaper", "video", "directory", "text"] }
            ]
        },
        {
            title: I18n.tr("Library watching"),
            subtitle: "",
            controls: [
                { id: "library.watch.status",
                  key: null,
                  kind: "static",
                  label: "%1",
                  searchTitle: I18n.tr("Watch status"),
                  help: "%2",
                  args: ["title", "detail"],
                  status: "library.status",
                  format: function (s, err) {
                      if (err || !s || !s.state)
                          return { title: I18n.tr("Watcher status unavailable"),
                                   detail: I18n.tr("The daemon did not report library-watch status. Restart it and reopen this page.") }
                      var ago = I18n.tr("not completed yet")
                      if (s.lastConvergence > 0) {
                          var secs = Math.max(0, Math.round(Date.now() / 1000 - s.lastConvergence))
                          ago = secs < 120 ? I18n.tr("%1 seconds ago").arg(secs) : I18n.tr("%1 minutes ago").arg(Math.round(secs / 60))
                      }
                      if (s.state === "native")
                          return { title: I18n.tr("Native file watching"),
                                   detail: I18n.tr("Filesystem events are active for %1 library folders. Polling is idle.").arg(s.watchedDirs) }
                      if (s.state === "polling")
                          return { title: I18n.tr("Polling fallback active"),
                                   detail: I18n.tr("Library folders are checked every %1 seconds (%2). Last change picked up: %3.").arg(s.pollingIntervalSeconds).arg(s.reason).arg(ago) }
                      if (s.state === "recovering")
                          return { title: I18n.tr("Native watching recovered"),
                                   detail: I18n.tr("The native watcher is active again; a full scan is still running before the library is current.") }
                      return { title: I18n.tr("Library watching unavailable"),
                               detail: I18n.tr("Native file watching failed (%1) and polling fallback is off. Turn on Polling fallback below.").arg(s.reason || I18n.tr("no library folder")) }
                  },
                  search: ["library.watch.status", "watch", "status", "inotify", "polling"] },
                { id: "library.pollingFallback",
                  key: "library.pollingFallback",
                  kind: "toggle",
                  label: I18n.tr("Polling fallback"),
                  help: "",
                  search: ["library.pollingFallback", "toggle"] },
                { id: "library.pollingIntervalSeconds",
                  key: "library.pollingIntervalSeconds",
                  kind: "number",
                  label: I18n.tr("Polling interval"),
                  help: "",
                  unit: I18n.tr("s"),
                  search: ["library.pollingIntervalSeconds", "number"] }
            ]
        },
        {
            title: I18n.tr("Images & recovery"),
            subtitle: "",
            controls: [
                { id: "performance.autoOptimizeImages",
                  key: "performance.autoOptimizeImages",
                  kind: "toggle",
                  label: I18n.tr("Auto-optimise new images"),
                  help: I18n.tr("Check new images as they arrive. An image is replaced only when the WebP passes the quality floor and saves enough space."),
                  search: ["performance.autoOptimizeImages", "auto", "optimise", "new", "images", "toggle"] },
                { id: "performance.imageOptimizePreset",
                  key: "performance.imageOptimizePreset",
                  kind: "dropdown",
                  label: I18n.tr("Quality"),
                  help: I18n.tr("Light: q82, 30 dB floor, 15% minimum savings. Balanced: q88, 32 dB, 10%. Quality: pixel-lossless WebP, 5%."),
                  options: [{ value: "light", label: I18n.tr("Light") }, { value: "balanced", label: I18n.tr("Balanced") }, { value: "quality", label: I18n.tr("Quality") }],
                  search: ["performance.imageOptimizePreset", "quality", "light", "balanced", "dropdown"] },
                { id: "performance.imageOptimizeResolution",
                  key: "performance.imageOptimizeResolution",
                  kind: "dropdown",
                  label: I18n.tr("Max resolution"),
                  help: I18n.tr("Images above the cap are downscaled. Smaller images are never upscaled."),
                  options: [{ value: "1080p", label: I18n.tr("1080p") }, { value: "2k", label: I18n.tr("2K") }, { value: "4k", label: I18n.tr("4K") }],
                  search: ["performance.imageOptimizeResolution", "max", "resolution", "1080p", "2k", "4k", "dropdown"] },
                { id: "performance.optimizeAll.action",
                  key: null,
                  kind: "action",
                  label: I18n.tr("Optimise all images"),
                  help: I18n.tr("Run image optimisation across the wallpaper library."),
                  action: "OptimizeImages",
                  search: ["optimise", "all", "images", "action"] },
                { id: "performance.imageTrashDays",
                  key: "performance.imageTrashDays",
                  kind: "number",
                  label: I18n.tr("Image retention"),
                  help: I18n.tr("Days to keep trashed images before auto-cleanup."),
                  unit: I18n.tr("days"),
                  search: ["performance.imageTrashDays", "image", "retention", "days", "number"] },
                { id: "performance.autoDeleteImageTrash",
                  key: "performance.autoDeleteImageTrash",
                  kind: "toggle",
                  label: I18n.tr("Auto-delete images after retention"),
                  help: I18n.tr("Permanently delete trashed images once they exceed the retention period."),
                  search: ["performance.autoDeleteImageTrash", "auto", "delete", "images", "retention", "toggle"] },
                { id: "performance.videoConvertPreset",
                  key: "performance.videoConvertPreset",
                  kind: "dropdown",
                  label: I18n.tr("Video conversion quality"),
                  help: I18n.tr("Quality used when converting videos to the efficient format."),
                  options: [{ value: "light", label: I18n.tr("Light") }, { value: "balanced", label: I18n.tr("Balanced") }, { value: "quality", label: I18n.tr("Quality") }],
                  enabledWhen: "available.videoOptimize",
                  disabledReason: I18n.tr("Video optimisation needs the libx265 encoder, which this system's ffmpeg does not provide."),
                  search: ["video", "convert"] },
                { id: "performance.videoConvertResolution",
                  key: "performance.videoConvertResolution",
                  kind: "dropdown",
                  label: I18n.tr("Video conversion resolution"),
                  help: I18n.tr("Largest resolution a converted video keeps."),
                  options: [{ value: "1080p", label: I18n.tr("1080p") }, { value: "2k", label: I18n.tr("2K") }, { value: "4k", label: I18n.tr("4K") }],
                  enabledWhen: "available.videoOptimize",
                  disabledReason: I18n.tr("Video optimisation needs the libx265 encoder, which this system's ffmpeg does not provide."),
                  search: ["video", "convert", "resolution"] },
                { id: "performance.convertAll.action",
                  key: null,
                  kind: "action",
                  label: I18n.tr("Convert all videos"),
                  help: I18n.tr("Convert every video wallpaper with the settings above."),
                  action: "ConvertVideos",
                  enabledWhen: "available.videoOptimize",
                  disabledReason: I18n.tr("Video optimisation needs the libx265 encoder, which this system's ffmpeg does not provide."),
                  search: ["video", "convert"] }
            ]
        },
        {
            title: I18n.tr("Generated variants"),
            subtitle: "",
            controls: [
                { id: "effects.autoRecolor",
                  key: "effects.autoRecolor",
                  kind: "toggle",
                  label: I18n.tr("Auto-recolour new wallpapers"),
                  help: I18n.tr("Save a recoloured copy beside every new wallpaper. Turn this off if you only want the original file."),
                  search: ["effects.autoRecolor", "auto", "recolour", "new", "wallpapers", "toggle"] },
                { id: "effects.autoTheme",
                  key: "effects.autoTheme",
                  kind: "dropdown",
                  label: I18n.tr("Recolour theme"),
                  help: I18n.tr("Palette used when auto-recolouring new wallpapers."),
                  dynamic: "recolourThemes",
                  search: ["effects.autoTheme", "recolour", "theme", "dropdown", "catppuccin"] }
            ]
        },
        {
            title: I18n.tr("Thumbnails & cache"),
            subtitle: "",
            controls: [
                { id: "performance.maxThumbJobs",
                  key: "performance.maxThumbJobs",
                  kind: "number",
                  label: I18n.tr("Max concurrent thumbnail jobs"),
                  help: I18n.tr("Number of thumbnail jobs that run in parallel during cache rebuilds."),
                  search: ["performance.maxThumbJobs", "max", "concurrent", "thumbnail", "jobs", "number"] },
                { id: "performance.captureWe.action",
                  key: null,
                  kind: "action",
                  label: I18n.tr("Add captured frame thumbnails to all WE wallpapers"),
                  help: I18n.tr("Capture native scenes in the background. Reuse valid captures and keep existing previews if a scene fails. You can stop and continue later."),
                  action: "CaptureWeThumbnails",
                  search: ["add", "captured", "frame", "thumbnails", "we", "wallpapers", "generate", "action"] },
                { id: "performance.clearCache.action",
                  key: null,
                  kind: "action",
                  label: I18n.tr("Clear all cached data"),
                  help: I18n.tr("Erase all cached thumbnails and regenerate from scratch on next scan."),
                  action: "ClearCache",
                  search: ["clear", "all", "cached", "data", "action"] },
                { id: "performance.recompute.action",
                  key: null,
                  kind: "action",
                  label: I18n.tr("Recompute colours"),
                  help: I18n.tr("Re-derive per-wallpaper colour bucket and saturation from existing thumbnails."),
                  action: "RecomputeColors",
                  search: ["recompute", "colours", "action"] },
                { id: "performance.videoCacheDays",
                  key: "performance.videoCacheDays",
                  kind: "number",
                  label: I18n.tr("Video cache retention"),
                  help: I18n.tr("Days a cached video copy is kept after it was last used."),
                  unit: I18n.tr("days"),
                  search: ["video", "cache", "retention"] },
                { id: "performance.autoCleanVideoCache",
                  key: "performance.autoCleanVideoCache",
                  kind: "toggle",
                  label: I18n.tr("Clean the video cache automatically"),
                  help: I18n.tr("Remove cached video copies older than the retention above."),
                  search: ["video", "cache", "clean"] },
                { id: "performance.clearVideoCache.action",
                  key: null,
                  kind: "action",
                  label: I18n.tr("Clear video cache"),
                  help: I18n.tr("Remove every cached video copy now."),
                  action: "ClearVideoCache",
                  search: ["video", "cache", "clear"] }
            ]
        }
    ]
}
