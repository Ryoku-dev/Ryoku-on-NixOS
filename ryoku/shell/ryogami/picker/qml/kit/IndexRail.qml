import QtQuick

Canvas {
    id: rail

    property int count: 0
    property int activeIndex: 0
    property real reveal: 1
    property real markerRadius: 5

    implicitWidth: 14 * Theme.scale
    renderTarget: Canvas.FramebufferObject

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onCountChanged: requestPaint()
    onActiveIndexChanged: requestPaint()
    onRevealChanged: requestPaint()
    Connections {
        target: Theme
        function onPaletteChanged() { rail.requestPaint() }
    }

    function _y(i) {
        var pad = rail.markerRadius * Theme.scale + 2
        var usable = Math.max(0, height - pad * 2)
        var n = Math.max(1, rail.count)
        return pad + usable * ((i + 0.5) / n)
    }

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        if (width <= 0 || height <= 0)
            return

        var cx = width / 2
        var s = Theme.scale

        ctx.lineWidth = 1
        ctx.strokeStyle = Theme.withAlpha(Theme.surfaceText, 0.16 * rail.reveal)
        ctx.beginPath()
        ctx.moveTo(cx, 0); ctx.lineTo(cx, height)
        ctx.stroke()

        for (var i = 0; i < rail.count; ++i) {
            var ny = rail._y(i)
            ctx.beginPath()
            ctx.arc(cx, ny, 1.5 * s, 0, Math.PI * 2)
            ctx.fillStyle = Theme.withAlpha(Theme.surfaceText, 0.28 * rail.reveal)
            ctx.fill()
        }

        if (rail.count > 0) {
            var y = rail._y(Math.max(0, Math.min(rail.count - 1, rail.activeIndex)))
            var r = rail.markerRadius * s * 0.7
            ctx.beginPath()
            ctx.arc(cx, y, r, 0, Math.PI * 2)
            ctx.fillStyle = Theme.withAlpha(Theme.surfaceText, rail.reveal)
            ctx.fill()
        }
    }
}
