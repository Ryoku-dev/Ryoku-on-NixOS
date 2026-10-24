import QtQuick
import Ryoku.Ui.Singletons

// Stepped by a timer at transition.previewFps, and only while visible.
Item {
    id: row

    property var control: ({})
    property var state
    property var options
    property real reveal: 1

    implicitHeight: col.implicitHeight

    readonly property string _family: String(Settings.value("transition.family") || "random")
    readonly property int _kind: {
        switch (row._family) {
        case "wipe": return 1;
        case "warp": return 2;
        case "break": return 3;
        case "sand": return 3;
        case "fade": return 0;
        default: return 0;
        }
    }
    readonly property int _fps: {
        var v = Number(Settings.value("transition.previewFps"));
        var cap = Number(Settings.value("general.maxFps"));
        if (isNaN(v) || v <= 0) v = 30;
        if (!isNaN(cap) && cap > 0) v = Math.min(v, cap);
        return Math.max(1, Math.min(120, Math.round(v)));
    }
    readonly property real _cycle: {
        var d = Number(Settings.value("transition.durationMs"));
        return Math.max(0.8, Math.min(5, (isNaN(d) || d <= 0 ? 900 : d) / 1000));
    }

    property real _progress: 0

    LibraryView {
        id: thumbs
        collection: "wallpapers"
    }
    readonly property url _thumbA: thumbs.count > 0 ? Library.fileUrl(thumbs.get(0).thumb || thumbs.get(0).path || "") : ""
    readonly property url _thumbB: thumbs.count > 1 ? Library.fileUrl(thumbs.get(1).thumb || thumbs.get(1).path || "") : row._thumbA

    Timer {
        interval: Math.round(1000 / row._fps)
        repeat: true
        running: row.visible
        onTriggered: {
            var step = (interval / 1000) / row._cycle;
            var next = row._progress + step;
            if (next >= 1.35)
                next = 0;
            row._progress = next;
        }
    }

    Column {
        id: col
        width: row.width
        spacing: 8 * Theme.scale

        Text {
            width: parent.width
            text: I18n.tr("Preview")
            font.family: Theme.sans
            font.weight: Font.Medium
            font.pixelSize: Theme.fontField
            color: Theme.withAlpha(Theme.surfaceText, row.reveal)
            renderType: Text.NativeRendering
        }

        Rectangle {
            id: stage
            width: Math.min(parent.width, 520 * Theme.scale)
            height: width * 9 / 16
            color: Theme.withAlpha(Theme.background, 0.9)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outline, 0.4)
            clip: true

            Image {
                id: imgA
                anchors.fill: parent
                source: row._thumbA
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
            }
            Image {
                id: imgB
                anchors.fill: parent
                source: row._thumbB
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
            }

            ShaderEffect {
                id: effect
                anchors.fill: parent
                visible: imgA.status === Image.Ready && imgB.status === Image.Ready
                property variant texA: imgA
                property variant texB: imgB
                property real progress: Math.min(1, row._progress)
                property int kind: row._kind
                fragmentShader: "qrc:/shaders/preview.frag.qsb"
            }

            Text {
                anchors.centerIn: parent
                visible: !effect.visible
                text: I18n.tr("Add wallpapers to preview transitions")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBody
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                renderType: Text.NativeRendering
            }
        }
    }
}
