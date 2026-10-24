import QtQuick
import Quickshell
import Quickshell.Io
import inir.modules.common
import inir.modules.common.widgets
import inir.modules.common.functions
import inir.services

/**
 * Thumbnail image. It currently generates to the right place at the right size, but does not handle metadata/maintenance on modification.
 * See Freedesktop's spec: https://specifications.freedesktop.org/thumbnail-spec/thumbnail-spec-latest.html
 */
StyledImage {
    id: root

    property bool generateThumbnail: true
    required property string sourcePath
    property string thumbnailSizeName: Images.thumbnailSizeNameForDimensions(sourceSize.width, sourceSize.height)
    property bool isVideo: Images.isValidVideoByName(sourcePath)
    // Videos use iNiR's own still: the shared freedesktop cache may hold a film-strip frame.
    property bool cleanVideoStill: false
    readonly property bool _ownsStill: root.cleanVideoStill && root.isVideo
    property bool thumbnailAvailable: false
    property string resolvedThumbnailSource: ""
    property string _queuedThumbnailCheck: ""
    property string thumbnailPath: {
        if (sourcePath.length === 0) return ""
        if (root._ownsStill) return Wallpapers.videoStillPath(sourcePath)

        let cleanPath = FileUtils.trimFileProtocol(String(sourcePath ?? ""))
        if (!cleanPath.startsWith("/"))
            cleanPath = Quickshell.env("PWD") + "/" + cleanPath

        const encodedParts = cleanPath.split("/").map(part => {
            return encodeURIComponent(part).replace(/[!'()*]/g, function(c) {
                return '%' + c.charCodeAt(0).toString(16)
            })
        })

        const md5Hash = Qt.md5("file://" + encodedParts.join("/"))
        return `${Directories.genericCache}/thumbnails/${thumbnailSizeName}/${md5Hash}.png`
    }
    source: {
        if (root.resolvedThumbnailSource.length > 0)
            return root.resolvedThumbnailSource
        // Ryoku generates no still image thumbnails; show the file itself,
        // bounded by the caller's sourceSize, rather than an empty tile.
        if (root._ownsStill || root.sourcePath.length === 0)
            return ""
        const clean = FileUtils.trimFileProtocol(String(root.sourcePath))
        return clean.startsWith("/") ? "file://" + clean : clean
    }

    asynchronous: true
    smooth: true
    mipmap: false

    opacity: status === Image.Ready ? 1 : 0
    Behavior on opacity {
        enabled: Appearance.animationsEnabled
        animation: NumberAnimation {
            duration: Appearance.calcEffectiveDuration(Appearance.animation.elementMoveFast.duration)
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    // Queue thumbnail generation through Wallpapers' serial queue instead of
    // spawning a per-item magick/ffmpeg process.  This avoids a thundering herd
    // when opening a directory with many uncached thumbnails.
    function _ensureThumbnail() {
        if (!root.generateThumbnail) return
        if (!root.sourcePath || root.sourcePath.length === 0) return
        // Batch generator already running — it will emit thumbnailGeneratedFile
        if (root._ownsStill) { Wallpapers.ensureVideoStill(root.sourcePath); return }
        if (Wallpapers.thumbnailGenerationRunning) return
        Wallpapers.ensureThumbnailForPath(root.sourcePath, root.thumbnailSizeName)
    }

    function _clearResolvedThumbnail() {
        root.thumbnailAvailable = false
        root.resolvedThumbnailSource = ""
    }

    function _startThumbnailCheck() {
        if (root._queuedThumbnailCheck.length === 0 || _thumbnailCheckProc.running) return
        const targetPath = root._queuedThumbnailCheck
        root._queuedThumbnailCheck = ""
        _thumbnailCheckProc._targetPath = targetPath
        _thumbnailCheckProc.command = ["test", "-f", targetPath]
        _thumbnailCheckProc.running = true
    }

    function reloadThumbnail() {
        if (!root.sourcePath || root.sourcePath.length === 0 || !root.thumbnailPath || root.thumbnailPath.length === 0) {
            root._queuedThumbnailCheck = ""
            root._clearResolvedThumbnail()
            return
        }

        const normalizedThumbnailPath = FileUtils.trimFileProtocol(root.thumbnailPath)
        if (Wallpapers.hasKnownThumbnail(normalizedThumbnailPath)) {
            root._queuedThumbnailCheck = ""
            root.thumbnailAvailable = true
            root.resolvedThumbnailSource = root.thumbnailPath
            return
        }

        root._clearResolvedThumbnail()
        root._queuedThumbnailCheck = normalizedThumbnailPath
        root._startThumbnailCheck()
    }

    onStatusChanged: {
        if (status === Image.Ready) {
            Wallpapers.rememberThumbnail(root.thumbnailPath)
        } else if (status === Image.Error && root.resolvedThumbnailSource.length > 0) {
            Wallpapers.forgetThumbnail(root.thumbnailPath)
            root.reloadThumbnail()
        }
    }

    onSourcePathChanged: {
        root.reloadThumbnail()
    }

    onThumbnailSizeNameChanged: {
        root.reloadThumbnail()
    }

    onSourceSizeChanged: {
        if (root.status === Image.Ready) return
        root.reloadThumbnail()
    }

    Process {
        id: _thumbnailCheckProc
        property string _targetPath: ""
        onExited: (exitCode) => {
            const currentThumbnailPath = FileUtils.trimFileProtocol(root.thumbnailPath)
            const checkedPath = _thumbnailCheckProc._targetPath

            if (checkedPath === currentThumbnailPath && exitCode === 0) {
                Wallpapers.rememberThumbnail(currentThumbnailPath)
                root.thumbnailAvailable = true
                root.resolvedThumbnailSource = root.thumbnailPath
            } else if (checkedPath === currentThumbnailPath) {
                Wallpapers.forgetThumbnail(currentThumbnailPath)
                root._clearResolvedThumbnail()
                root._ensureThumbnail()
            }

            if (root._queuedThumbnailCheck.length === 0
                    && currentThumbnailPath.length > 0
                    && checkedPath !== currentThumbnailPath
                    && !Wallpapers.hasKnownThumbnail(currentThumbnailPath)) {
                root._queuedThumbnailCheck = currentThumbnailPath
            }

            root._startThumbnailCheck()
        }
    }
}
