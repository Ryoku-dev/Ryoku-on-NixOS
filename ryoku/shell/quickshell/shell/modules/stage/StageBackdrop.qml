pragma ComponentBehavior: Bound
import QtQuick
import stage.services
import "../wallpaper" as WallpaperMod
import "Singletons"

// The Stage backdrop, drawn inside the desktop surface just above the base
// wallpaper: the inpainted background.png behind the cut-outs, a flat plane
// without a depth map, a depth-displaced 3D scene with one.
Item {
    id: root

    property var screen
    property string wallpaperPath: ""
    readonly property string screenName: root.screen ? root.screen.name : ""
    readonly property var wallpaperGeometry: WallpaperLayout.geometryFor(root.screenName)
    property string wallpaperFit: "Cover"
    property bool spatialEnabled: true
    property bool layered: false

    anchors.fill: parent

    readonly property bool owns: StageBackend.isActiveFor(root.wallpaperPath)
    readonly property bool parallax: StageBackend.isParallaxFor(root.wallpaperPath)
    readonly property string url: StageBackend.backdropUrlFor(root.wallpaperPath)
    readonly property string depthUrl: StageBackend.depthUrlFor(root.wallpaperPath)
    readonly property bool spatial: root.spatialEnabled && root.url !== "" && root.depthUrl !== ""
    readonly property bool shown: root.owns && root.url !== ""

    readonly property real cursorNX: StageBackend.cursorNXFor(root.screenName)
    readonly property real cursorNY: StageBackend.cursorNYFor(root.screenName)
    readonly property real _max: root.width * 0.04
    readonly property real _gain: root.parallax && !root.spatial && Config.followMouse
        ? Config.amountFactor * Config.sensitivity * Config.backdrop * 0.25 : 0
    readonly property real _cameraGain: root.spatial && Config.followMouse
        ? Config.amountFactor * Config.sensitivity * Config.range : 0
    function offsetX() { return root.cursorNX * root._max * root._gain; }
    function offsetY() { return root.cursorNY * root._max * root._gain; }

    function fillModeFor(im) {
        switch (root.wallpaperFit) {
        case "Contain": return Image.PreserveAspectFit;
        case "Fill": return Image.Stretch;
        case "ScaleDown":
            return (im.sourceSize.width <= root.width && im.sourceSize.height <= root.height)
                ? Image.Pad : Image.PreserveAspectFit;
        default: return Image.PreserveAspectCrop;
        }
    }

    Item {
        id: visual
        anchors.fill: parent
        transform: Translate {
            x: root.offsetX()
            y: root.offsetY()
            Behavior on x { SmoothedAnimation { velocity: 320; duration: 70 } }
            Behavior on y { SmoothedAnimation { velocity: 320; duration: 70 } }
        }

        WallpaperMod.WallpaperFramedPlane {
            id: framedBackdrop
            anchors.fill: parent
            screenName: root.screenName
            framingKey: root.wallpaperPath
            imageWidth: root.wallpaperGeometry?.imageWidth ?? bg.sourceSize.width
            imageHeight: root.wallpaperGeometry?.imageHeight ?? bg.sourceSize.height

            Image {
                id: bg
                anchors.fill: parent
                source: root.url
                cache: false
                asynchronous: true
                fillMode: framedBackdrop.framed ? Image.PreserveAspectCrop : root.fillModeFor(bg)
                sourceSize.width: root.width
                sourceSize.height: root.height
                // The framing owns the crop; pointer drift moves the completed
                // plane in screen coordinates on top of that transform.
                opacity: (root.shown && status === Image.Ready) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }

            Loader {
                id: sceneLoader
                anchors.fill: parent
                active: root.spatial
                visible: status === Loader.Ready

                sourceComponent: Component {
                    StageSpatialScene {
                        backgroundPath: root.url
                        depthPath: root.depthUrl
                        mattePath: StageBackend.layerUrlFor(root.wallpaperPath, 0)
                        textureSize: Qt.size(root.width, root.height)
                        stretch: root.wallpaperFit === "Fill"
                        screenName: root.screenName
                        layered: root.layered
                        pointerX: root.cursorNX
                        pointerY: root.cursorNY
                        motionAmount: root._cameraGain
                    }
                }
            }
        }
    }

    HoverHandler {
        enabled: root.owns
        acceptedButtons: Qt.NoButton
        onPointChanged: {
            const m = root.screen;
            if (!m || root.width <= 0 || root.height <= 0) return;
            StageBackend.setCursor(m.name,
                point.position.x / root.width * 2 - 1,
                point.position.y / root.height * 2 - 1);
        }
    }
}

