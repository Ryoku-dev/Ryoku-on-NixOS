import QtQuick
import Quickshell.Widgets
import "../clock"
import stage.modules.common.functions
import ".."

/**
 * A file as a small picture: images as a cropped thumbnail decoded at the
 * size shown, everything else as its type symbol on a tinted plate.
 */
Item {
    id: thumb

    property string path: ""
    property real radius: ClockStyle.radiusSmall
    // Decode larger than shown when the dock lens may enlarge it.
    property real renderScale: 1
    property color colPlate: ClockStyle.colSecondaryContainer
    property color colSymbol: ClockStyle.colOnSecondaryContainer
    readonly property bool image: UtilityFiles.isImage(thumb.path)

    Rectangle {
        anchors.fill: parent
        visible: !thumb.image || picture.status !== Image.Ready
        radius: thumb.radius
        color: thumb.colPlate

        TileSymbol {
            anchors.centerIn: parent
            text: UtilityFiles.symbolFor(thumb.path)
            iconSize: Math.round(Math.min(parent.width, parent.height) * 0.5)
            fill: 1
            color: thumb.colSymbol
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        visible: thumb.image && picture.status === Image.Ready
        radius: thumb.radius
        color: "transparent"

        StyledImage {
            id: picture
            anchors.fill: parent
            source: thumb.image && thumb.path ? UtilityFiles.fileUri(thumb.path) : ""
            sourceSize: Qt.size(
                Math.ceil(thumb.width * Math.max(1.5, thumb.renderScale * 1.25)),
                Math.ceil(thumb.height * Math.max(1.5, thumb.renderScale * 1.25)))
            fillMode: Image.PreserveAspectCrop
            cache: false
            smooth: true
        }
    }
}
