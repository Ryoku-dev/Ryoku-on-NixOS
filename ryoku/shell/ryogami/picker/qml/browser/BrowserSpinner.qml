import QtQuick

// Spun by a render-thread RotationAnimator, so nothing runs on the JS thread while it turns.
Item {
    id: spinner

    property color color: Theme.surfaceText
    property real size: 48

    implicitWidth: spinner.size * Theme.scale
    implicitHeight: spinner.size * Theme.scale

    Canvas {
        id: ring
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
            target: Theme
            function onPaletteChanged() { ring.requestPaint() }
        }
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (width <= 0 || height <= 0)
                return
            var lw = Math.max(2, width * 0.11)
            var r = (Math.min(width, height) - lw) / 2
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.strokeStyle = spinner.color
            ctx.beginPath()
            ctx.arc(width / 2, height / 2, r, -Math.PI / 2, Math.PI, false)
            ctx.stroke()
        }

        RotationAnimator on rotation {
            from: 0; to: 360
            duration: 900
            loops: Animation.Infinite
            running: spinner.visible
        }
    }
}
