import QtQuick
import Quickshell
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property var descriptor: ({ path: "", name: "", kind: "default", bytes: 0, enabled: true })
    property bool active: true
    property bool forceDefault: false
    onMediaPathChanged: {
        orientationKnown = false
        imageTall = false
    }

    readonly property string mediaPath: descriptor && typeof descriptor.path === "string" ? descriptor.path : ""
    readonly property string mediaKind: descriptor && typeof descriptor.kind === "string" ? descriptor.kind : "default"
    readonly property bool customEnabled: !descriptor || descriptor.enabled !== false
    readonly property bool wantsVideo: customEnabled && mediaPath !== "" && mediaKind === "video"
    readonly property bool wantsImage: customEnabled && mediaPath !== "" && (mediaKind === "image" || mediaKind === "animated")
    // brand.json stores an absolute path today, but a hand-edited or ported
    // config may carry a ~ (the shell expands it for the brand mark too); a bare
    // "file://~/..." resolves to nothing and silently falls back to the default
    // cover, so expand it here before building the URL.
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string resolvedPath: mediaPath === "~"
        ? root.homeDir
        : (mediaPath.indexOf("~/") === 0 ? root.homeDir + mediaPath.substring(1) : mediaPath)
    readonly property string imageSource: resolvedPath.indexOf("://") >= 0 ? resolvedPath : "file://" + resolvedPath
    readonly property size orientationProbeSize: Qt.size(64, 64)
    property bool orientationKnown: false
    property bool imageTall: false
    readonly property bool probeReady: imageProbeLoader.status === Loader.Ready
        && imageProbeLoader.item
        && imageProbeLoader.item.status === Image.Ready
    readonly property bool probeFailed: imageProbeLoader.status === Loader.Ready
        && imageProbeLoader.item
        && imageProbeLoader.item.status === Image.Error
    readonly property bool probeReleased: wantsImage && orientationKnown
        && imageProbeLoader.status === Loader.Null
    readonly property bool imageReady: wantsImage
        && customImageLoader.status === Loader.Ready
        && customImageLoader.item
        && customImageLoader.item.status === Image.Ready
    readonly property bool videoReady: videoLoader.status === Loader.Ready && videoLoader.item && videoLoader.item.ready
    readonly property bool customReady: customEnabled && !forceDefault && (imageReady || videoReady)
    readonly property bool mediaError: wantsImage
        ? probeFailed
            || (orientationKnown && (customImageLoader.status === Loader.Error
                || (customImageLoader.status === Loader.Ready
                    && customImageLoader.item
                    && customImageLoader.item.status === Image.Error)))
        : (wantsVideo && (videoLoader.status === Loader.Error
            || (videoLoader.status === Loader.Ready && videoLoader.item && videoLoader.item.failed)))
    readonly property string mediaErrorText: wantsVideo && videoLoader.status === Loader.Ready && videoLoader.item
        ? videoLoader.item.errorText
        : ""
    readonly property bool showingDefault: forceDefault || !customReady
    readonly property real defaultLogoWidth: Math.min(width * 0.58, 928)
    readonly property real defaultLogoHeight: defaultLogoWidth * 160 / 928

    // The bundled wordmark with its loading light sweep: the cue that the
    // cover is working, not frozen. Lost in the ReloadMedia refactor merge;
    // restored here where the default mark now lives.
    Item {
        id: defaultLogo
        anchors.centerIn: parent
        width: root.defaultLogoWidth
        height: root.defaultLogoHeight
        visible: root.showingDefault

        Image {
            id: logo
            anchors.fill: parent
            source: "assets/logo.png"
            sourceSize.width: Math.round(root.defaultLogoWidth)
            fillMode: Image.PreserveAspectFit
        }

        Item {
            id: loadingSweep
            x: defaultLogo.width
            width: Math.max(36, defaultLogo.width * 0.24)
            height: defaultLogo.height
            clip: true

            ColorOverlay {
                x: -loadingSweep.x
                width: defaultLogo.width
                height: defaultLogo.height
                source: logo
                color: "#e2f0ff"
                opacity: 0.28
            }

            NumberAnimation on x {
                from: defaultLogo.width
                to: -loadingSweep.width
                duration: 1200
                running: defaultLogo.visible && root.active
                loops: Animation.Infinite
            }
        }
    }

    Component {
        id: orientationProbe
        Image {
            objectName: "imageProbe"
            source: root.imageSource
            fillMode: Image.PreserveAspectFit
            sourceSize: root.orientationProbeSize
            asynchronous: true
            cache: false
            onStatusChanged: {
                if (status === Image.Ready) {
                    root.imageTall = implicitHeight > implicitWidth
                    root.orientationKnown = true
                }
            }
        }
    }

    Loader {
        id: imageProbeLoader
        objectName: "imageProbeLoader"
        active: root.wantsImage && !root.orientationKnown && !root.forceDefault
        sourceComponent: orientationProbe
    }

    Component {
        id: wideImage
        AnimatedImage {
            objectName: "customImage"
            anchors.fill: parent
            source: root.imageSource
            sourceSize.width: Math.max(1, Math.ceil(width))
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            playing: root.active && root.imageReady && !root.forceDefault && status === Image.Ready
        }
    }

    Component {
        id: tallImage
        AnimatedImage {
            objectName: "customImage"
            anchors.fill: parent
            source: root.imageSource
            sourceSize.height: Math.max(1, Math.ceil(height))
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            playing: root.active && root.imageReady && !root.forceDefault && status === Image.Ready
        }
    }

    Loader {
        id: customImageLoader
        anchors.fill: parent
        active: root.wantsImage && root.orientationKnown && !root.forceDefault
        visible: root.imageReady && !root.forceDefault
        sourceComponent: root.imageTall ? tallImage : wideImage
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.active && root.wantsVideo && !root.forceDefault
        source: active ? Qt.resolvedUrl("ReloadVideo.qml") : ""
        onLoaded: {
            if (status === Loader.Ready && item) {
                item.path = Qt.binding(() => root.resolvedPath)
                item.active = Qt.binding(() => root.active && !root.forceDefault)
            }
        }
    }
}
