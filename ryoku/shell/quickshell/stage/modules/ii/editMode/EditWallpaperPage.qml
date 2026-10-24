import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import stage
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.common.functions
import Ryoku.Ui.Singletons

/**
 * The wallpaper folder, as a grid of thumbnails on Edit Mode's panel.
 *
 * A compact cut of the full selector: the folder the shell already watches,
 * in the order it is already sorted, three to a row. A click applies and the
 * card follows; the applied one carries a mark. Sorting, search, sub-folders
 * and the online browser stay with the selector, which the Style page hands
 * off to.
 *
 * A screen target goes straight to Ryogami's per-output selector. Lock and
 * light-mode variants retain their existing services.
 */
Item {
    id: root

    // "desktop", "lockscreen", "lightmode" or "screen".
    property string target: "desktop"
    // The screen a "screen" pick is for.
    property string screenName: ""
    readonly property bool screenTarget: root.target === "screen"
    readonly property string appliedPath: {
        if (root.screenTarget)
            return Wallpapers.currentWallpaperPath(root.screenName);
        if (root.target === "desktop")
            return Wallpapers.currentWallpaperPath();
        const background = Config.options.background;
        const raw = root.target === "lockscreen" ? background.lockscreenWallpaperPath
            : background.lightModeWallpaperPath;
        return FileUtils.trimFileProtocol(String(raw ?? ""));
    }

    readonly property real cellGap: Tokens.s2
    readonly property real minimumCellWidth: Tokens.cellH
    readonly property int columns: Math.max(1, Math.min(3,
        Math.floor((Math.max(0, grid.width) + root.cellGap) / (root.minimumCellWidth + root.cellGap))))
    // The gap belongs to the stride, keeping the final column inside the view.
    readonly property real cellStride: Math.floor(Math.max(0, grid.width) / root.columns)
    readonly property real cellWidth: Math.max(1, root.cellStride - root.cellGap)
    readonly property real cellHeight: Math.round(root.cellWidth * 10 / 16)

    // Ryogami's index is the library of record, including its separate video
    // directory and nested folders. Before its first scan, keep the source
    // folder model as the usable fallback.
    readonly property var files: {
        const library = Wallpapers.ryogamiLibraryModel;
        const model = library.count > 0 ? library : Wallpapers.sortedFolderModel;
        const out = [];
        const count = model.count;
        for (let i = 0; i < count; i++) {
            const entry = model.get(i);
            if (!entry || entry.fileIsDir)
                continue;
            const name = String(entry.fileName ?? "");
            const lowerName = name.toLowerCase();
            if (!Wallpapers.extensions.some(ext => lowerName.endsWith("." + ext)))
                continue;
            out.push({
                "filePath": FileUtils.trimFileProtocol(String(entry.filePath ?? "")),
                "fileName": name
            });
        }
        return out;
    }

    function apply(path) {
        if (root.screenTarget) {
            Wallpapers.selectForScreen(path, root.screenName);
            return;
        }
        if (root.target === "lockscreen") {
            Wallpapers.selectLockscreen(path);
            return;
        }
        if (root.target === "lightmode") {
            Wallpapers.selectLightmode(path);
            return;
        }
        Wallpapers.select(path);
    }

    Component.onCompleted: Wallpapers.load()

    GridView {
        id: grid
        anchors.fill: parent
        anchors.margins: Tokens.s2
        clip: true
        cellWidth: root.cellStride
        cellHeight: root.cellHeight + root.cellGap
        model: root.files
        boundsBehavior: Flickable.StopAtBounds
        maximumFlickVelocity: 3500

        TouchpadScrollHandler {
            flickable: grid
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool applied: cell.modelData.filePath === root.appliedPath
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: tile
                width: root.cellWidth
                height: root.cellHeight
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer1
                border.width: cell.applied ? 2 : 0
                border.color: cell.applied ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                scale: tileMouse.containsPress ? 0.96 : 1
                Behavior on scale {
                    enabled: !Appearance.reducedMotion
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(tile)
                }

                ClippingRectangle {
                    anchors.fill: parent
                    anchors.margins: tile.border.width
                    radius: tile.radius - tile.border.width
                    color: "transparent"

                    Item {
                        id: thumbnail
                        anchors.fill: parent
                        readonly property real dpr: (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1
                        readonly property string filePath: cell.modelData.filePath
                        readonly property bool video: Wallpapers.isVideoFile(thumbnail.filePath)
                        readonly property string ryogamiPath: {
                            void Wallpapers.ryogamiIndexRevision;
                            return Wallpapers.ryogamiThumbnailPath(thumbnail.filePath);
                        }

                        Image {
                            id: ryogamiThumbnail
                            anchors.fill: parent
                            source: Wallpapers.localFileUrl(thumbnail.ryogamiPath)
                            sourceSize.width: Math.max(1, Math.ceil(width * thumbnail.dpr))
                            sourceSize.height: Math.max(1, Math.ceil(height * thumbnail.dpr))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            visible: status === Image.Ready
                        }

                        Loader {
                            anchors.fill: parent
                            active: thumbnail.ryogamiPath === "" || ryogamiThumbnail.status === Image.Error
                            sourceComponent: Image {
                                readonly property int posterRevision: Wallpapers.videoPosterRevision
                                readonly property string fallbackPath: thumbnail.video
                                    ? Wallpapers.videoPosterPath(thumbnail.filePath)
                                    : thumbnail.filePath
                                readonly property string fallbackUrl: Wallpapers.localFileUrl(fallbackPath)
                                source: fallbackUrl === "" ? ""
                                    : fallbackUrl + (thumbnail.video ? `?v=${posterRevision}` : "")
                                sourceSize.width: Math.max(1, Math.ceil(width * thumbnail.dpr))
                                sourceSize.height: Math.max(1, Math.ceil(height * thumbnail.dpr))
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                Component.onCompleted: {
                                    if (thumbnail.video)
                                        Wallpapers.ensureVideoPoster(thumbnail.filePath);
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    visible: cell.applied
                    width: 22
                    height: 22
                    radius: width / 2
                    color: Appearance.colors.colPrimary

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        iconSize: 16
                        color: Appearance.colors.colOnPrimary
                    }
                }

                // No tooltip with the file's name: a StyledToolTip inside a
                // view's delegate draws itself without a hover.
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!cell.applied)
                            root.apply(cell.modelData.filePath);
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        width: Math.max(0, root.width - Tokens.s5 * 2)
        visible: grid.count === 0
        text: Wallpapers.directoryLoading ? Translation.tr("Loading…") : Translation.tr("No wallpapers in this folder")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnSurfaceVariant
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
