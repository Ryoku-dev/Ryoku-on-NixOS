import QtQuick

/**
 * A panel window's content, drawn into the Stage Editor's card.
 *
 * Fills its window. While the editor frames this monitor the window grows
 * across the screen on the axis away from its edge (`extent`), keeping its
 * anchors and its exclusive zone, so nothing reflows; the content stays in
 * `rest`, a strip of the window's normal thickness against its edge, and the
 * whole layer carries the desktop's matrix. At progress 0 the matrix is the
 * identity, so growing and shrinking the window never shows.
 *
 * The window binds its size across the edge to `extent`, parents its content
 * into this layer (it lands in `rest`), and maps every input-mask rect through
 * `maskRect`, given in `rest`'s coordinates.
 */
Item {
    id: root

    required property string screenName
    // "top" | "bottom" | "left" | "right": the edge the window is anchored to.
    required property string edge
    // The window's thickness away from that edge while not framed.
    required property real restThickness
    required property real screenWidth
    required property real screenHeight
    // The window's own origin on the screen, for one held off it by margins.
    property real originX: 0
    property real originY: 0
    // A surface the card only shows (a bar: its popups belong to the real
    // screen, not the card) sets this false; while framed it then takes no
    // input and its mask is empty, so clicks reach the card beneath it.
    property bool interactive: true

    default property alias content: rest.data
    readonly property alias rest: rest

    readonly property bool framed: StageFrame.framing(root.screenName)
    readonly property bool horizontal: root.edge === "top" || root.edge === "bottom"
    readonly property real extent: root.framed
        ? (root.horizontal ? root.screenHeight : root.screenWidth)
        : root.restThickness

    function maskRect(x: real, y: real, width: real, height: real): rect {
        if (root.framed && !root.interactive)
            return Qt.rect(0, 0, 0, 0);
        return StageFrame.mapRect(root.screenName, root.screenWidth, root.screenHeight,
            root.originX, root.originY, Qt.rect(rest.x + x, rest.y + y, width, height));
    }

    enabled: root.interactive || !root.framed

    anchors.fill: parent
    transform: Matrix4x4 {
        matrix: StageFrame.matrixFor(root.screenName, root.screenWidth, root.screenHeight, root.originX, root.originY)
    }

    Item {
        id: rest
        x: root.edge === "right" ? root.width - root.restThickness : 0
        y: root.edge === "bottom" ? root.height - root.restThickness : 0
        width: root.horizontal ? root.width : root.restThickness
        height: root.horizontal ? root.restThickness : root.height
    }
}
