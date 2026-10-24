import QtQuick
import Quickshell
import stage.services
import "../.."

Image {
    asynchronous: !source.toString().startsWith("image://icon/")
    retainWhileLoading: true
    visible: opacity > 0
    opacity: (status === Image.Ready) ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    property list<string> fallbacks: []
    property int currentFallbackIndex: 0

    onStatusChanged: {
        if (status === Image.Error && currentFallbackIndex < fallbacks.length) {
            source = fallbacks[currentFallbackIndex];
            currentFallbackIndex += 1;
        }
    }

    // Decode at the drawn size, in device pixels. A side the image sizes itself
    // (no anchors, or a layout slot that drops it while it loads) keeps its last
    // request: its width is the decoded width, so asking for width * dpr again
    // grows the image by the scale factor on every load at a fractional scale.
    // The window caps the request, so no layout can feed a side back unbounded.
    // The check is deferred until width and implicit width have both settled.
    property size decodeSize: Qt.size(0, 0)
    readonly property real decodeScale: (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1
    sourceSize: decodeSize

    function decodeSide(side: real, implicitSide: real, current: int, windowSide: real): int {
        if (side <= 0 || side === implicitSide)
            return current;
        const limit = windowSide > 0 ? Math.ceil(windowSide * decodeScale) : 8192;
        return Math.min(Math.ceil(side * decodeScale), limit);
    }
    function syncDecodeSize(): void {
        const window = QsWindow.window;
        const next = Qt.size(decodeSide(width, implicitWidth, decodeSize.width, window?.width ?? 0),
            decodeSide(height, implicitHeight, decodeSize.height, window?.height ?? 0));
        if (next.width !== decodeSize.width || next.height !== decodeSize.height)
            decodeSize = next;
    }
    onWidthChanged: Qt.callLater(syncDecodeSize)
    onHeightChanged: Qt.callLater(syncDecodeSize)
    onImplicitWidthChanged: Qt.callLater(syncDecodeSize)
    onImplicitHeightChanged: Qt.callLater(syncDecodeSize)
    onDecodeScaleChanged: Qt.callLater(syncDecodeSize)
}
