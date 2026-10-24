pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import shell.services as Ryoku
import inir.services.deferred
import inir.services
import inir.modules.common
import inir.modules.common.widgets
import inir.modules.iris.components
import inir.modules.iris.style

ColumnLayout {
    id: root

    readonly property real d: IrisStyle.density
    readonly property bool spectrumEnabled: Config.options?.iris?.equalizer?.spectrum?.enabled ?? true
    readonly property string spectrumStyle: String(Config.options?.iris?.equalizer?.spectrum?.style ?? "capsules")
    readonly property real spectrumOpacity: Math.max(0, Math.min(1, Number(Config.options?.iris?.equalizer?.spectrum?.opacity ?? 0.5)))
    readonly property bool wantsSpectrum: root.visible && root.spectrumEnabled
    readonly property int trackHeight: Math.round(190 * root.d)
    property int spectrumSubscription: -1

    spacing: Math.round(10 * root.d)

    function syncSpectrum(): void {
        if (root.wantsSpectrum && root.spectrumSubscription < 0)
            root.spectrumSubscription = CavaService.subscribe(64)
        else if (!root.wantsSpectrum && root.spectrumSubscription >= 0) {
            CavaService.unsubscribe(root.spectrumSubscription)
            root.spectrumSubscription = -1
        }
    }

    onWantsSpectrumChanged: root.syncSpectrum()
    onSpectrumStyleChanged: spectrum.requestPaint()
    Component.onCompleted: root.syncSpectrum()
    Component.onDestruction: {
        if (root.spectrumSubscription >= 0)
            CavaService.unsubscribe(root.spectrumSubscription)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(8 * root.d)

        IrisText {
            text: Translation.tr("10-band curve")
            role: IrisText.Eyebrow
        }
        Item { Layout.fillWidth: true }
        IrisText {
            text: Ryoku.Equalizer.on
                ? (Ryoku.Equalizer.running ? Translation.tr("Active") : Translation.tr("Starting"))
                : Translation.tr("Bypassed")
            color: Ryoku.Equalizer.on ? IrisStyle.accent : IrisStyle.muted
            font.pixelSize: IrisStyle.typeFootnote
        }
    }

    Item {
        id: field
        Layout.fillWidth: true
        Layout.preferredHeight: root.trackHeight + Math.round(54 * root.d)

        Rectangle {
            anchors.fill: parent
            radius: IrisStyle.radiusCard
            color: IrisStyle.fillQuiet
            border.width: 1
            border.color: IrisStyle.hairline
        }

        Canvas {
            id: spectrum
            anchors.fill: parent
            anchors.margins: Math.round(12 * root.d)
            visible: root.spectrumEnabled
            opacity: root.spectrumOpacity

            function sampleAt(index, count) {
                const points = CavaService.points ?? []
                if (points.length === 0) return 0
                const at = count <= 1 ? 0 : Math.round(index * (points.length - 1) / (count - 1))
                return Math.max(0, Math.min(1, Number(points[at] ?? 0) / Math.max(1, CavaService.normalizationCeiling)))
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (!root.spectrumEnabled || width <= 0 || height <= 0) return
                const count = 48
                const gap = Math.max(1, width / count * 0.28)
                const step = width / count
                const base = height - Math.round(16 * root.d)
                ctx.fillStyle = IrisStyle.accent
                ctx.strokeStyle = IrisStyle.accent
                if (root.spectrumStyle === "wave") {
                    ctx.lineWidth = Math.max(1, 2 * root.d)
                    ctx.beginPath()
                    for (let i = 0; i < count; ++i) {
                        const x = (i + 0.5) * step
                        const y = base - spectrum.sampleAt(i, count) * height * 0.72
                        if (i === 0) ctx.moveTo(x, y)
                        else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                } else if (root.spectrumStyle === "ring") {
                    let average = 0
                    for (let i = 0; i < count; ++i) average += spectrum.sampleAt(i, count)
                    average /= count
                    const radius = Math.min(width, height) * (0.16 + average * 0.2)
                    ctx.lineWidth = Math.max(2, 8 * root.d)
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, radius, 0, Math.PI * 2)
                    ctx.stroke()
                } else {
                    for (let i = 0; i < count; ++i) {
                        const level = spectrum.sampleAt(i, count)
                        const x = i * step + gap / 2
                        const h = Math.max(2 * root.d, level * height * 0.72)
                        if (root.spectrumStyle === "dots") {
                            ctx.beginPath()
                            ctx.arc(x + (step - gap) / 2, base - h, Math.max(1.5, 2.5 * root.d), 0, Math.PI * 2)
                            ctx.fill()
                        } else if (root.spectrumStyle === "capsules") {
                            ctx.lineWidth = Math.max(2, step - gap)
                            ctx.lineCap = "round"
                            ctx.beginPath()
                            ctx.moveTo(x + (step - gap) / 2, base)
                            ctx.lineTo(x + (step - gap) / 2, base - h)
                            ctx.stroke()
                        } else {
                            ctx.fillRect(x, base - h, Math.max(1, step - gap), h)
                        }
                    }
                }
            }

            Connections {
                target: CavaService
                function onPointsChanged(): void { spectrum.requestPaint() }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onVisibleChanged: requestPaint()
        }

        Row {
            id: bandRow
            anchors.fill: parent
            anchors.leftMargin: Math.round(12 * root.d)
            anchors.rightMargin: Math.round(12 * root.d)
            anchors.topMargin: Math.round(8 * root.d)
            anchors.bottomMargin: Math.round(8 * root.d)

            Repeater {
                model: Ryoku.Equalizer.bandCount

                Item {
                    id: band
                    required property int index

                    width: bandRow.width / Ryoku.Equalizer.bandCount
                    height: bandRow.height
                    activeFocusOnTab: true
                    property bool dragging: false
                    property int dragDb: 0
                    readonly property int db: band.dragging ? band.dragDb : Math.round(Ryoku.Equalizer.gainAt(band.index))
                    readonly property real fraction: (band.db + Ryoku.Equalizer.range) / (2 * Ryoku.Equalizer.range)

                    function dbAt(y: real): int {
                        const usable = Math.max(1, root.trackHeight - knob.height)
                        const fraction = 1 - Math.max(0, Math.min(1, (y - knob.height / 2) / usable))
                        return Math.round(fraction * 2 * Ryoku.Equalizer.range - Ryoku.Equalizer.range)
                    }
                    function nudge(amount: int): void {
                        Ryoku.Equalizer.setBand(band.index, band.db + amount)
                    }

                    Keys.onUpPressed: band.nudge(1)
                    Keys.onDownPressed: band.nudge(-1)
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) {
                            Ryoku.Equalizer.setBand(band.index, Ryoku.Equalizer.range)
                            event.accepted = true
                        } else if (event.key === Qt.Key_End) {
                            Ryoku.Equalizer.setBand(band.index, -Ryoku.Equalizer.range)
                            event.accepted = true
                        }
                    }
                    Keys.onSpacePressed: Ryoku.Equalizer.setBand(band.index, 0)

                    Timer {
                        id: livePush
                        interval: 90
                        onTriggered: Ryoku.Equalizer.setBand(band.index, band.dragDb)
                    }

                    IrisText {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: String(Ryoku.Equalizer.bandLabels[band.index] ?? "")
                        color: band.activeFocus || bandMouse.containsMouse ? IrisStyle.accent : IrisStyle.textSecondary
                        font.pixelSize: IrisStyle.typeFootnote
                        font.family: IrisStyle.fontNumbers
                    }

                    Rectangle {
                        id: track
                        anchors.top: parent.top
                        anchors.topMargin: Math.round(24 * root.d)
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round(8 * root.d)
                        height: root.trackHeight
                        radius: width / 2
                        color: IrisStyle.surfaceHigh
                        border.width: 1
                        border.color: band.activeFocus || bandMouse.containsMouse || band.dragging
                            ? IrisStyle.accent : IrisStyle.hairline

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 1
                            height: Math.max(0, (parent.height - 2) * band.fraction)
                            radius: width / 2
                            color: Ryoku.Equalizer.on ? IrisStyle.accent : IrisStyle.muted
                            opacity: Ryoku.Equalizer.on ? 0.8 : 0.45
                            Behavior on height {
                                NumberAnimation {
                                    duration: band.dragging ? 0 : IrisStyle.duration(180)
                                    easing.type: IrisStyle.feedbackEasing
                                }
                            }
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: Math.round(parent.height / 2)
                            width: parent.width + Math.round(7 * root.d)
                            height: 1
                            color: IrisStyle.textSecondary
                            opacity: 0.5
                        }
                    }

                    Rectangle {
                        id: knob
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.round((band.dragging || band.activeFocus ? 15 : 13) * root.d)
                        height: width
                        radius: width / 2
                        y: track.y + (track.height - height) * (1 - band.fraction)
                        color: IrisStyle.bodySurface
                        border.width: 2
                        border.color: Ryoku.Equalizer.on ? IrisStyle.accent : IrisStyle.muted
                        Behavior on y {
                            NumberAnimation {
                                duration: band.dragging ? 0 : IrisStyle.duration(180)
                                easing.type: IrisStyle.feedbackEasing
                            }
                        }
                    }

                    MouseArea {
                        id: bandMouse
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: track.y
                        width: Math.max(Math.round(26 * root.d), band.width)
                        height: track.height
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            band.forceActiveFocus()
                            band.dragDb = band.dbAt(mouse.y)
                            band.dragging = true
                            livePush.restart()
                        }
                        onPositionChanged: mouse => {
                            if (!band.dragging) return
                            const next = band.dbAt(mouse.y)
                            if (next === band.dragDb) return
                            band.dragDb = next
                            if (!livePush.running) livePush.restart()
                        }
                        onReleased: {
                            livePush.stop()
                            Ryoku.Equalizer.setBand(band.index, band.dragDb)
                            band.dragging = false
                        }
                        onCanceled: {
                            livePush.stop()
                            band.dragging = false
                        }
                        onDoubleClicked: Ryoku.Equalizer.setBand(band.index, 0)
                        onWheel: wheel => {
                            band.nudge(wheel.angleDelta.y >= 0 ? 1 : -1)
                            wheel.accepted = true
                        }
                    }

                    IrisText {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (band.db > 0 ? "+" : "") + band.db
                        color: band.dragging || bandMouse.containsMouse || band.activeFocus ? IrisStyle.accent : IrisStyle.muted
                        font.pixelSize: IrisStyle.typeFootnote
                        font.family: IrisStyle.fontNumbers
                    }

                    Accessible.role: Accessible.Slider
                    Accessible.name: Translation.tr("%1 Hz band").arg(String(Ryoku.Equalizer.bandLabels[band.index] ?? ""))
                    Accessible.description: Translation.tr("%1 dB").arg(band.db)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Math.round(8 * root.d)

        IrisButton {
            text: Translation.tr("Flatten")
            quiet: true
            buttonRadius: height / 2
            onClicked: Ryoku.Equalizer.applyPreset("Flat")
        }
        IrisButton {
            text: Ryoku.Equalizer.on ? Translation.tr("Bypass") : Translation.tr("Turn on")
            emphasized: !Ryoku.Equalizer.on
            quiet: Ryoku.Equalizer.on
            buttonRadius: height / 2
            onClicked: Ryoku.Equalizer.setOn(!Ryoku.Equalizer.on)
        }
        Item { Layout.fillWidth: true }
        IrisText {
            text: root.peakText
            color: IrisStyle.muted
            font.pixelSize: IrisStyle.typeFootnote
            font.family: IrisStyle.fontNumbers
        }
    }

    readonly property string peakText: {
        let high = 0
        let low = 0
        for (const gain of Array.from(Ryoku.Equalizer.gains ?? [])) {
            high = Math.max(high, Number(gain) || 0)
            low = Math.min(low, Number(gain) || 0)
        }
        if (Math.abs(high) < 0.05 && Math.abs(low) < 0.05)
            return Translation.tr("Flat")
        const hi = (high > 0 ? "+" : "") + high.toFixed(0)
        const lo = (low > 0 ? "+" : "") + low.toFixed(0)
        return Translation.tr("Peak %1 / %2 dB").arg(hi).arg(lo)
    }
}
