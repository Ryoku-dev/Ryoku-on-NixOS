pragma ComponentBehavior: Bound

import QtQuick
import stage.services
import stage.modules.common.functions

Item {
    id: root

    default property alias framedData: content.data

    property string screenName: ""
    property string framingKey: ""
    property real imageWidth: 0
    property real imageHeight: 0

    readonly property var framing: WallpaperLayout.framingFor(root.screenName, root.framingKey)
    readonly property real framingAngle: WallpaperLayout.angleFor(root.screenName, root.framingKey)
    readonly property bool framed: !WallpaperFraming.isIdentity(root.framing)
        || Math.abs(root.framingAngle % 360) > 0.001
    readonly property var frame: WallpaperFraming.layout(root.width, root.height,
        root.imageWidth, root.imageHeight, root.framing, root.framingAngle)
    readonly property Item contentItem: content

    Item {
        id: content
        width: root.framed ? root.frame.width : root.width
        height: root.framed ? root.frame.height : root.height
        x: root.framed ? (root.width - width) / 2 + root.frame.x : 0
        y: root.framed ? (root.height - height) / 2 + root.frame.y : 0
        rotation: root.framed ? root.frame.angle : 0
        transform: Scale {
            origin.x: content.width / 2
            origin.y: content.height / 2
            xScale: root.framed ? root.frame.scaleX : 1
            yScale: root.framed ? root.frame.scaleY : 1
        }
    }
}
