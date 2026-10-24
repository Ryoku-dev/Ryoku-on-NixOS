import QtQuick
import QtQuick3D
import Ryoku.Spatial3D 1.0
import "Singletons"

// The background half of the Stage scene: a depth-displaced mesh under the
// separate cut-out, lit only by its own texture. The camera orbits the map's
// 0.5 pivot plane so near and far relief separate without moving the cut-out.
Item {
    id: root

    property url backgroundPath
    property url depthPath
    property url mattePath
    property size textureSize: Qt.size(Math.max(1, width), Math.max(1, height))
    property real pointerX: 0
    property real pointerY: 0
    property real motionAmount: 0
    property bool stretch: false
    property string screenName: ""

    readonly property real pivotDistance: depthGeometry.valid ? depthGeometry.focusDistance : 0
    function publishPivot() {
        if (root.screenName !== "")
            StageBackend.setSpatialPivot(root.screenName, root.pivotDistance);
    }
    onPivotDistanceChanged: root.publishPivot()
    onScreenNameChanged: root.publishPivot()

    readonly property real outputAspect: width > 0 && height > 0 ? width / height : 16 / 9
    readonly property real imageZoom: StageBackend.spatialZoom
    readonly property real focusZ: -depthGeometry.focusDistance
    readonly property vector2d boundedPointer: Qt.vector2d(
        Math.max(-1, Math.min(1, pointerX)),
        Math.max(-1, Math.min(1, pointerY)))
    readonly property real sourceAspect: backgroundInfo.implicitHeight > 0
        ? backgroundInfo.implicitWidth / backgroundInfo.implicitHeight : outputAspect
    readonly property bool ready: depthGeometry.valid && backgroundInfo.status === Image.Ready

    Image {
        id: backgroundInfo
        visible: false
        source: root.backgroundPath
        sourceSize: root.textureSize
        asynchronous: true
        cache: false
    }

    Texture {
        id: wallTexture
        source: root.backgroundPath
        generateMipmaps: true
        minFilter: Texture.Linear
        magFilter: Texture.Linear
        mipFilter: Texture.Linear
        tilingModeHorizontal: Texture.ClampToEdge
        tilingModeVertical: Texture.ClampToEdge
    }

    View3D {
        id: view
        anchors.fill: parent
        visible: root.ready
        camera: sceneCamera
        // The mesh covers the viewport, so MSAA has no silhouette to improve.
        // Inline avoids a full-output intermediate texture and its extra pass.
        renderMode: View3D.Inline
        environment: SceneEnvironment {
            backgroundMode: SceneEnvironment.Transparent
            antialiasingMode: SceneEnvironment.NoAA
        }

        PerspectiveCamera {
            id: sceneCamera
            fieldOfView: 42
            fieldOfViewOrientation: PerspectiveCamera.Vertical
            clipNear: 0.01
            clipFar: 100
            position: Qt.vector3d(0, 0, 0)
        }

        Model {
            position: Qt.vector3d(0, 0, -depthGeometry.backgroundDistance)
            source: "#Rectangle"
            scale: Qt.vector3d(
                root.imageZoom * 2 * depthGeometry.backgroundDistance
                    * Math.tan(Math.PI * 42 / 360) * root.outputAspect / 100,
                root.imageZoom * 2 * depthGeometry.backgroundDistance
                    * Math.tan(Math.PI * 42 / 360) / 100, 1)
            materials: CustomMaterial {
                shadingMode: CustomMaterial.Unshaded
                cullMode: Material.NoCulling
                vertexShader: Qt.resolvedUrl("shaders/spatial_background.vert")
                fragmentShader: Qt.resolvedUrl("shaders/spatial_background.frag")
                property TextureInput backgroundTexture: TextureInput {
                    texture: wallTexture
                }
            }
        }

        Model {
            geometry: DepthMeshGeometry {
                id: depthGeometry
                depthPath: root.depthPath
                mattePath: root.mattePath
                imageZoom: root.imageZoom
                outputAspect: root.outputAspect
                sourceAspect: root.sourceAspect
                fitMode: root.stretch ? DepthMeshGeometry.Stretch : DepthMeshGeometry.Crop
            }
            materials: CustomMaterial {
                shadingMode: CustomMaterial.Unshaded
                cullMode: Material.NoCulling
                vertexShader: Qt.resolvedUrl("shaders/spatial_background.vert")
                fragmentShader: Qt.resolvedUrl("shaders/spatial_background.frag")
                property TextureInput backgroundTexture: TextureInput {
                    texture: wallTexture
                }
            }
        }
    }

    function updateCamera() {
        const gain = Math.max(0, Math.min(1.5, root.motionAmount))
        const yaw = root.boundedPointer.x * Math.PI * 2.5 / 180 * gain
        const pitch = -root.boundedPointer.y * Math.PI * 1.8 / 180 * gain
        const radius = depthGeometry.focusDistance
        sceneCamera.position = Qt.vector3d(
            Math.sin(yaw) * Math.cos(pitch) * radius,
            Math.sin(pitch) * radius,
            root.focusZ + Math.cos(yaw) * Math.cos(pitch) * radius)
        sceneCamera.lookAt(Qt.vector3d(0, 0, root.focusZ))
    }
    onBoundedPointerChanged: updateCamera()
    onMotionAmountChanged: updateCamera()
    onOutputAspectChanged: updateCamera()
    Connections {
        target: depthGeometry
        function onFocusDistanceChanged() { root.updateCamera() }
    }
    Component.onCompleted: {
        root.publishPivot();
        root.updateCamera();
    }
}
