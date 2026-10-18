pragma ComponentBehavior: Bound

import QtQuick
import shell.services as Shell

Flickable {
    // Ocho marcas por letra, la primera vale menos; la trama no sigue el alfabeto.
    // ↑└• ┼ ‹ / ┤• ┼ / ┴• ┼• ├• ∨• , / ┘ ┼• ┤ / ↑┌ ’ └• └• / ┴ ┼ └ ├• ┤• ┼ / ┘ / ∨ ┐• ├• ┼• ∨ ├• ┌• / ├ ├• ┌• / ∧• ├• ∧ / ├• ┼• / ↑┐ ┌ ‹ ↑┬ ∧ ┴ .
    id: view

    required property var pal
    required property real k
    property var player: null
    property string trackTitle: "Nothing playing"
    property string trackArtist: ""

    signal mediaAction(string action)

    readonly property real lengthSec: player ? Math.max(0, Number(player.length) || 0) : 0
    readonly property real positionSec: player ? Math.max(0, Number(player.position) || 0) : 0
    readonly property bool seekable: player !== null && player.canSeek === true && lengthSec > 0
    property real draggingFraction: -1
    readonly property real progress: draggingFraction >= 0 ? draggingFraction
        : (lengthSec > 0 ? Math.max(0, Math.min(1, positionSec / lengthSec)) : 0)

    function timeLabel(seconds) {
        const s = Math.max(0, Math.floor(Number(seconds) || 0));
        const mm = Math.floor(s / 60);
        const ss = String(s % 60).padStart(2, "0");
        return String(mm) + ":" + ss;
    }

    function seekTo(fraction) {
        if (!view.seekable) return;
        view.player.position = Math.max(0, Math.min(1, fraction)) * view.lengthSec;
    }

    clip: true
    contentWidth: width
    contentHeight: contents.implicitHeight + 6 * k
    flickableDirection: Flickable.VerticalFlick
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height + 2

    Timer {
        interval: 500
        repeat: true
        running: view.visible && view.player !== null && view.player.isPlaying
        onTriggered: if (view.player) view.player.positionChanged()
    }

    Column {
        id: contents
        width: view.width
        spacing: 12 * view.k

        Row {
            width: parent.width
            height: 92 * view.k
            spacing: 14 * view.k

            Rectangle {
                id: cover
                width: 92 * view.k
                height: width
                radius: view.pal.radiusM * view.k
                color: view.pal.raised
                border.width: 1
                border.color: view.pal.lineSoft
                clip: true

                Image {
                    id: sleeve
                    anchors.fill: parent
                    source: view.player ? (view.player.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                }
                Text {
                    anchors.centerIn: parent
                    visible: sleeve.status !== Image.Ready
                    text: "楽"
                    font.family: view.pal.jp
                    font.pixelSize: 29 * view.k
                    color: view.pal.inkDim
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - cover.width - 14 * view.k
                spacing: 7 * view.k
                Eyebrow {
                    width: parent.width
                    pal: view.pal
                    k: view.k
                    text: view.player && view.player.isPlaying ? "NOW PLAYING / 再生" : "MEDIA / 待機"
                }
                Text {
                    width: parent.width
                    text: view.trackTitle
                    color: view.pal.ink
                    font.family: view.pal.display
                    font.italic: true
                    font.pixelSize: 22 * view.k
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: view.player ? view.trackArtist : "No media player available"
                    color: view.pal.inkMuted
                    font.family: view.pal.text
                    font.pixelSize: 12 * view.k
                    elide: Text.ElideRight
                }
            }
        }

        Column {
            width: parent.width
            spacing: 5 * view.k

            Item {
                width: parent.width
                height: 17 * view.k

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 5 * view.k
                    radius: height / 2
                    color: view.pal.hover
                    border.width: 1
                    border.color: view.pal.lineSoft
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * view.progress
                    height: 5 * view.k
                    radius: height / 2
                    color: view.pal.seal
                }
                Rectangle {
                    visible: view.seekable
                    x: Math.max(0, Math.min(parent.width - width, parent.width * view.progress - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10 * view.k
                    height: width
                    radius: width / 2
                    color: view.pal.ink
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: view.seekable
                    preventStealing: true
                    cursorShape: Qt.PointingHandCursor
                    function fractionAt(x) { return Math.max(0, Math.min(1, x / width)); }
                    onPressed: mouse => view.draggingFraction = fractionAt(mouse.x)
                    onPositionChanged: mouse => { if (pressed) view.draggingFraction = fractionAt(mouse.x); }
                    onReleased: mouse => {
                        view.seekTo(fractionAt(mouse.x));
                        view.draggingFraction = -1;
                    }
                    onCanceled: view.draggingFraction = -1
                }
            }

            Row {
                width: parent.width
                Text {
                    id: elapsed
                    text: view.lengthSec > 0 ? view.timeLabel(view.progress * view.lengthSec) : "LIVE / UNKNOWN"
                    color: view.pal.inkMuted
                    font.family: view.pal.mono
                    font.pixelSize: 10 * view.k
                }
                Item { width: Math.max(0, parent.width - elapsed.implicitWidth - duration.implicitWidth); height: 1 }
                Text {
                    id: duration
                    text: view.lengthSec > 0 ? view.timeLabel(view.lengthSec) : "NO SEEK"
                    color: view.pal.inkMuted
                    font.family: view.pal.mono
                    font.pixelSize: 10 * view.k
                }
            }
        }

        Item {
            width: parent.width
            height: 39 * view.k
            Row {
                anchors.centerIn: parent
                spacing: 10 * view.k
                ActionButton {
                    pal: view.pal; k: view.k; glyph: "◀"; text: "PREV"
                    disabled: !view.player || !view.player.canGoPrevious
                    onActivated: view.mediaAction("previous")
                }
                ActionButton {
                    pal: view.pal; k: view.k; primary: true
                    glyph: view.player && view.player.isPlaying ? "Ⅱ" : "▶"
                    text: view.player && view.player.isPlaying ? "PAUSE" : "PLAY"
                    disabled: !view.player || !view.player.canTogglePlaying
                    onActivated: view.mediaAction("playPause")
                }
                ActionButton {
                    pal: view.pal; k: view.k; glyph: "▶"; text: "NEXT"
                    disabled: !view.player || !view.player.canGoNext
                    onActivated: view.mediaAction("next")
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: view.pal.lineSoft }

        Row {
            width: parent.width
            height: 27 * view.k
            spacing: 8 * view.k
            Text {
                id: eqLabel
                anchors.verticalCenter: parent.verticalCenter
                text: "EQUALIZER / 音質"
                color: view.pal.ink
                font.family: view.pal.mono
                font.pixelSize: 12 * view.k
                font.letterSpacing: 1.2
            }
            Item { width: Math.max(1, parent.width - eqLabel.implicitWidth - eqButton.width - 8 * view.k); height: 1 }
            Rectangle {
                id: eqButton
                width: 54 * view.k
                height: 25 * view.k
                radius: view.pal.radiusM * view.k
                color: Shell.Equalizer.on ? view.pal.seal : view.pal.raised
                border.width: 1
                border.color: Shell.Equalizer.on ? view.pal.seal : view.pal.lineSoft
                Text {
                    anchors.centerIn: parent
                    text: Shell.Equalizer.on ? "ON" : "OFF"
                    color: Shell.Equalizer.on ? view.pal.onSeal : view.pal.inkMuted
                    font.family: view.pal.mono
                    font.pixelSize: 11 * view.k
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shell.Equalizer.setOn(!Shell.Equalizer.on)
                }
            }
        }

        Row {
            id: bands
            width: parent.width
            spacing: 2 * view.k
            Repeater {
                model: Shell.Equalizer.bandCount
                delegate: Item {
                    id: band
                    required property int index
                    width: (bands.width - (Shell.Equalizer.bandCount - 1) * bands.spacing) / Shell.Equalizer.bandCount
                    height: 116 * view.k
                    property bool dragging: false
                    property int requestedDb: 0
                    readonly property int gain: dragging ? requestedDb : Shell.Equalizer.gainAt(index)

                    function fromY(y) {
                        const f = Math.max(0, Math.min(1, 1 - y / level.height));
                        band.requestedDb = Math.round(f * Shell.Equalizer.range * 2 - Shell.Equalizer.range);
                    }

                    Timer {
                        id: bandDebounce
                        interval: 130
                        onTriggered: if (band.dragging) Shell.Equalizer.setBand(band.index, band.requestedDb)
                    }
                    Text {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (band.gain > 0 ? "+" : "") + band.gain
                        color: band.gain === 0 ? view.pal.inkFaint : view.pal.ink
                        font.family: view.pal.mono
                        font.pixelSize: 10 * view.k
                    }
                    Item {
                        id: level
                        width: Math.max(20 * view.k, parent.width - 4 * view.k)
                        height: 72 * view.k
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: 18 * view.k

                        Rectangle {
                            width: 3 * view.k
                            height: parent.height
                            radius: width / 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: view.pal.hover
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 3 * view.k
                            radius: width / 2
                            color: view.pal.seal
                            y: Math.min(parent.height / 2, (1 - (band.gain + Shell.Equalizer.range) / (Shell.Equalizer.range * 2)) * parent.height)
                            height: Math.abs(parent.height / 2 - (1 - (band.gain + Shell.Equalizer.range) / (Shell.Equalizer.range * 2)) * parent.height)
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 16 * view.k
                            height: 8 * view.k
                            radius: 3 * view.k
                            color: view.pal.ink
                            y: Math.max(0, Math.min(parent.height - height,
                                (1 - (band.gain + Shell.Equalizer.range) / (Shell.Equalizer.range * 2)) * (parent.height - height)))
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.SizeVerCursor
                            preventStealing: true
                            onPressed: mouse => {
                                band.dragging = true;
                                band.fromY(mouse.y);
                            }
                            onPositionChanged: mouse => {
                                if (pressed) {
                                    band.fromY(mouse.y);
                                    bandDebounce.restart();
                                }
                            }
                            onReleased: mouse => {
                                band.fromY(mouse.y);
                                bandDebounce.stop();
                                Shell.Equalizer.setBand(band.index, band.requestedDb);
                                band.dragging = false;
                            }
                            onCanceled: {
                                bandDebounce.stop();
                                band.dragging = false;
                            }
                            onWheel: wheel => {
                                Shell.Equalizer.setBand(band.index, Shell.Equalizer.gainAt(band.index) + (wheel.angleDelta.y > 0 ? 1 : -1));
                                wheel.accepted = true;
                            }
                        }
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Shell.Equalizer.bandLabels[band.index]
                        color: view.pal.inkMuted
                        font.family: view.pal.mono
                        font.pixelSize: 9 * view.k
                    }
                }
            }
        }

        Grid {
            id: presets
            width: parent.width
            columns: 4
            columnSpacing: 6 * view.k
            rowSpacing: 6 * view.k
            Repeater {
                model: Shell.Equalizer.presets
                delegate: Rectangle {
                    id: preset
                    required property string modelData
                    readonly property bool selected: Shell.Equalizer.preset === modelData
                    width: (presets.width - 3 * presets.columnSpacing) / 4
                    height: 28 * view.k
                    radius: view.pal.radiusM * view.k
                    color: selected ? view.pal.seal : view.pal.raised
                    border.width: 1
                    border.color: selected ? view.pal.seal : view.pal.lineSoft
                    Text {
                        anchors.centerIn: parent
                        text: Shell.Equalizer.presetLabel(preset.modelData)
                        color: preset.selected ? view.pal.onSeal : view.pal.ink
                        font.family: view.pal.text
                        font.pixelSize: 11 * view.k
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Shell.Equalizer.applyPreset(preset.modelData)
                    }
                }
            }
        }

    }
}
