import QtQuick

Item {
    id: wheel

    // h in degrees (0..360); s and v in 0..1.
    property var hsv: ({ h: 0, s: 0, v: 1 })

    signal hue(real deg)
    signal sv(real s, real v)
    signal dragEnd()

    readonly property real ringFraction: 0.16
    readonly property int wedges: 90

    implicitWidth: 184 * Theme.scale
    implicitHeight: 184 * Theme.scale

    readonly property real _cx: width / 2
    readonly property real _cy: height / 2
    readonly property real _outer: Math.min(width, height) / 2 - 2 * Theme.scale
    readonly property real _inner: _outer * 0.84
    readonly property real _sqHalf: (_inner - 6 * Theme.scale) / Math.SQRT2

    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onHsvChanged: canvas.requestPaint()

    // 0 none, 1 ring, 2 square.
    property int _drag: 0
    property bool _over: false

    Canvas {
        id: canvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width <= 0 || height <= 0)
                return

            var cx = wheel._cx, cy = wheel._cy
            var outer = wheel._outer, inner = wheel._inner, half = wheel._sqHalf
            var h = Number(wheel.hsv.h) || 0
            var s = Number(wheel.hsv.s) || 0
            var v = Number(wheel.hsv.v)
            if (isNaN(v)) v = 1

            // Punch the disc back to the page colour so only the annulus remains.
            var step = (Math.PI * 2) / wheel.wedges
            for (var k = 0; k < wheel.wedges; k++) {
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.arc(cx, cy, outer, k * step, (k + 1) * step + 0.004, false)
                ctx.closePath()
                ctx.fillStyle = Qt.hsva((k + 0.5) / wheel.wedges, 1, 1, 1)
                ctx.fill()
            }
            ctx.beginPath()
            ctx.arc(cx, cy, inner, 0, Math.PI * 2, false)
            ctx.fillStyle = Theme.surface
            ctx.fill()

            var cells = 28
            var cw = (half * 2) / cells
            for (var i = 0; i < cells; i++) {
                var cs = i / (cells - 1)
                for (var j = 0; j < cells; j++) {
                    var cv = 1 - j / (cells - 1)
                    ctx.fillStyle = Qt.hsva(h / 360, cs, cv, 1)
                    ctx.fillRect(cx - half + i * cw, cy - half + j * cw, cw + 1, cw + 1)
                }
            }
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.withAlpha(Theme.outline, 0.6)
            ctx.strokeRect(cx - half, cy - half, half * 2, half * 2)

            var ringR = (outer + inner) / 2
            var ha = h * Math.PI / 180
            var hr = (outer - inner) * 0.42
            wheel._marker(ctx, cx + ringR * Math.cos(ha), cy + ringR * Math.sin(ha), hr, hr + 1.5 * Theme.scale)

            var mx = cx - half + s * half * 2
            var my = cy - half + (1 - v) * half * 2
            wheel._marker(ctx, mx, my, 6 * Theme.scale, 7.5 * Theme.scale)
        }
    }

    // A black outline under a white stroke, so it reads on any hue.
    function _marker(ctx, x, y, rWhite, rBlack) {
        ctx.lineWidth = 1
        ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.9)
        ctx.beginPath()
        ctx.arc(x, y, rBlack, 0, Math.PI * 2, false)
        ctx.stroke()
        ctx.lineWidth = 2
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.95)
        ctx.beginPath()
        ctx.arc(x, y, rWhite, 0, Math.PI * 2, false)
        ctx.stroke()
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: (wheel._drag !== 0 || wheel._over) ? Qt.CrossCursor : Qt.ArrowCursor

        function _classify(x, y) {
            var dx = x - wheel._cx, dy = y - wheel._cy
            var d = Math.sqrt(dx * dx + dy * dy)
            if (d >= wheel._inner * 0.92 && d <= wheel._outer * 1.08)
                return 1
            if (Math.abs(dx) <= wheel._sqHalf && Math.abs(dy) <= wheel._sqHalf)
                return 2
            return 0
        }
        function _emitHue(x, y) {
            var a = Math.atan2(y - wheel._cy, x - wheel._cx)
            wheel.hue((a * 180 / Math.PI + 360) % 360)
        }
        function _emitSv(x, y) {
            var s = (x - (wheel._cx - wheel._sqHalf)) / (wheel._sqHalf * 2)
            var v = 1 - (y - (wheel._cy - wheel._sqHalf)) / (wheel._sqHalf * 2)
            wheel.sv(Math.max(0, Math.min(1, s)), Math.max(0, Math.min(1, v)))
        }

        onPressed: (mouse) => {
            wheel._drag = _classify(mouse.x, mouse.y)
            if (wheel._drag === 1)
                _emitHue(mouse.x, mouse.y)
            else if (wheel._drag === 2)
                _emitSv(mouse.x, mouse.y)
        }
        onPositionChanged: (mouse) => {
            wheel._over = _classify(mouse.x, mouse.y) !== 0
            if (wheel._drag === 1)
                _emitHue(mouse.x, mouse.y)
            else if (wheel._drag === 2)
                _emitSv(mouse.x, mouse.y)
        }
        onReleased: (mouse) => {
            if (wheel._drag !== 0) {
                wheel._drag = 0
                wheel.dragEnd()
            }
        }
        onExited: wheel._over = false
    }
}
