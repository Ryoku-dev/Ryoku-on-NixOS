import inir.modules.common
import inir.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

MaterialShape { // App icon
    id: root
    property var appIcon: ""
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    property bool isUrgent: urgency === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: implicitSize * materialIconScale
    property real appIconSize: implicitSize * appIconScale
    property real smallAppIconSize: implicitSize * smallAppIconScale

    readonly property string imageValue: String(image ?? "")
    readonly property bool imageIsIconHint: imageValue.startsWith("image://icon/")
    readonly property string hintedIcon: imageIsIconHint ? imageValue.substring(13) : ""
    readonly property string appIconValue: String(appIcon ?? "").trim()
    readonly property bool appIconIsFileUrl: appIconValue.startsWith("file://")
    readonly property string effectiveAppIcon: appIconValue.length > 0 ? appIconValue : hintedIcon
    readonly property string defaultMaterialSymbol: NotificationUtils.findSuitableMaterialSymbol("")
    readonly property string guessedMaterialSymbol: NotificationUtils.findSuitableMaterialSymbol(String(summary ?? ""))
    readonly property bool preferMaterialSymbol: guessedMaterialSymbol !== defaultMaterialSymbol
        && ((appIconValue.length === 0 && imageIsIconHint)
            || (appIconIsFileUrl && String(summary ?? "").toLowerCase().includes("screenshot")))
    readonly property bool hasVisualImage: imageValue.length > 0 && !imageIsIconHint

    function resolveAppIcon(value) {
        let raw = String(value ?? "").trim()
        if (raw.length === 0)
            return ""
        if (raw.startsWith("image://icon/"))
            raw = decodeURIComponent(raw.substring(13))
        else if (raw.startsWith("/") || raw.startsWith("file:") || raw.indexOf(":") > 0)
            return raw
        return Quickshell.iconPath(raw, "")
    }
    readonly property string resolvedAppIcon: root.resolveAppIcon(root.effectiveAppIcon)
    readonly property string resolvedSmallAppIcon: root.resolveAppIcon(root.appIconValue)
    property bool appIconFailed: false
    property bool smallAppIconFailed: false
    onResolvedAppIconChanged: root.appIconFailed = false
    onResolvedSmallAppIconChanged: root.smallAppIconFailed = false

    implicitSize: 38 * scale
    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst,
    ]
    shape: isUrgent ? urgentShapes[Math.floor(Math.random() * urgentShapes.length)] : MaterialShape.Shape.Circle

    color: Appearance.zzzEverywhere
        ? (isUrgent ? Appearance.zzz.secondary : Appearance.zzz.paperAlt)
        : isUrgent ? Appearance.colors.colPrimaryContainer : "transparent"
    Loader {
        id: materialSymbolLoader
        // Icon-theme hints such as notify-send's `-i camera-photo` are not
        // notification artwork. Prefer a semantic Material Symbol when the
        // summary identifies one (for example screenshot notifications).
        active: root.preferMaterialSymbol
            || (!root.hasVisualImage && (root.resolvedAppIcon === "" || root.appIconFailed))
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                return (root.urgency == NotificationUrgency.Critical
                    && root.guessedMaterialSymbol === root.defaultMaterialSymbol)
                    ? "priority_high" : root.guessedMaterialSymbol
            }
            anchors.fill: parent
            color: Appearance.zzzEverywhere
                ? (isUrgent ? Appearance.zzz.onSecondary : Appearance.zzz.ink)
                : isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: appIconLoader
        active: !root.hasVisualImage && !root.preferMaterialSymbol
            && root.resolvedAppIcon !== "" && !root.appIconFailed
        anchors.centerIn: parent
        sourceComponent: IconImage {
            id: appIconImage
            implicitSize: root.appIconSize
            asynchronous: true
            source: root.resolvedAppIcon
            onStatusChanged: if (status === Image.Error) root.appIconFailed = true
        }
    }
    Loader {
        id: notifImageLoader
        active: root.hasVisualImage
        anchors.fill: parent
        sourceComponent: Item {
            id: notifImageContainer
            anchors.fill: parent
            property bool imageValid: true
            Image {
                id: notifImage
                anchors.fill: parent
                readonly property int size: parent.width
                visible: status === Image.Ready

                source: notifImageContainer.imageValid ? root.image : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true

                width: size
                height: size
                sourceSize.width: size
                sourceSize.height: size
                onStatusChanged: {
                    if (status === Image.Error) {
                        notifImageContainer.imageValid = false
                        notifImageLoader.active = false
                    }
                }

                layer.enabled: status === Image.Ready
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: notifImage.size
                        height: notifImage.size
                        radius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full
                        Behavior on radius {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                        }
                    }
                }
            }
            Item {
                id: notifImageAppIcon
                visible: root.appIconValue.length > 0
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: root.smallAppIconSize
                height: root.smallAppIconSize

                IconImage {
                    anchors.fill: parent
                    visible: root.resolvedSmallAppIcon !== "" && !root.smallAppIconFailed
                    implicitSize: root.smallAppIconSize
                    asynchronous: true
                    source: root.resolvedSmallAppIcon
                    onStatusChanged: if (status === Image.Error) root.smallAppIconFailed = true
                }
                MaterialSymbol {
                    anchors.fill: parent
                    visible: root.resolvedSmallAppIcon === "" || root.smallAppIconFailed
                    text: "notifications"
                    color: Appearance.zzzEverywhere ? Appearance.zzz.ink : Appearance.colors.colOnSecondaryContainer
                    iconSize: root.smallAppIconSize
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
