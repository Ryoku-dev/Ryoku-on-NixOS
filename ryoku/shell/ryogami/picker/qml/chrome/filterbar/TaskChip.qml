import QtQuick
import Ryoku.Ui.Singletons

// One background job: its name, how far it has got, a hairline that fills as it runs,
// then only the controls the job allows.
Row {
    id: chip

    required property var task

    readonly property string taskId: String(chip.task.id || "")
    readonly property string taskState: String(chip.task.state || "")
    readonly property int total: Math.max(Number(chip.task.total || 0), 0)
    readonly property int done: Math.min(Math.max(Number(chip.task.progress || 0), 0), chip.total)
    readonly property var caps: chip.task.capabilities || ({})
    readonly property bool failed: chip.taskState === "failed"

    spacing: 2 * Theme.scale
    height: 30 * Theme.scale

    function _name() {
        if (chip.taskId === "semantic-index") return I18n.tr("Index")
        if (chip.taskId === "scan") return I18n.tr("Scan")
        if (chip.taskId.indexOf("download:") === 0) return I18n.tr("Download")
        if (chip.taskId === "we-thumbnails") return I18n.tr("Scene thumbnails")
        return String(chip.task.label || chip.taskId)
    }
    // Downloads count in percent; the other jobs count items. A state word shows only
    // when the job is not simply running.
    function _detail() {
        var s = ""
        switch (chip.taskState) {
        case "paused": s = I18n.tr("paused"); break
        case "completed": s = I18n.tr("done"); break
        case "failed": s = I18n.tr("failed"); break
        case "cancelled": s = I18n.tr("stopped"); break
        }
        var n = ""
        if (chip.total > 0) {
            if (chip.task.kind === "download") n = Math.round(100 * chip.done / chip.total) + "%"
            else if (chip.taskState === "completed") n = String(chip.total)
            else n = chip.done + "/" + chip.total
        }
        return s !== "" && n !== "" ? n + " " + s : (n !== "" ? n : s)
    }

    Item {
        id: face
        width: body.implicitWidth + 20 * Theme.scale
        height: parent.height
        HoverHandler { id: faceHover }

        Row {
            id: body
            anchors.centerIn: parent
            spacing: 7 * Theme.scale
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 6 * Theme.scale
                height: width
                radius: width
                color: chip.failed ? Theme.tertiary : Theme.surfaceText
                SequentialAnimation on opacity {
                    running: chip.taskState === "running"
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip._name()
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fs(12)
                color: chip.failed ? Theme.tertiary : Theme.surfaceText
                renderType: Text.NativeRendering
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: text.length > 0
                text: chip._detail()
                font.family: Theme.sans
                font.pixelSize: Theme.fs(11.5)
                font.features: { "tnum": 1 }
                color: Theme.withAlpha(Theme.surfaceText, 0.58)
                renderType: Text.NativeRendering
            }
        }
        Rectangle {
            anchors.left: body.left
            anchors.top: body.bottom
            anchors.topMargin: 3 * Theme.scale
            width: body.width
            height: 1
            color: Theme.withAlpha(Theme.surfaceText, 0.16)
            visible: chip.taskState === "running" && chip.total > 0
            Rectangle {
                height: parent.height
                width: parent.width * chip.done / Math.max(chip.total, 1)
                color: Theme.surfaceText
                Behavior on width { NumberAnimation { duration: Theme.standard; easing.type: Easing.OutCubic } }
            }
        }
        Rectangle {
            visible: tipText.text.length > 0
            opacity: faceHover.hovered ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.fast } }
            anchors.top: parent.bottom
            anchors.topMargin: 6 * Theme.scale
            anchors.horizontalCenter: parent.horizontalCenter
            width: tipText.implicitWidth + 16 * Theme.scale
            height: tipText.implicitHeight + 10 * Theme.scale
            radius: Theme.radius
            color: Theme.surfaceText
            z: 50
            Text {
                id: tipText
                anchors.centerIn: parent
                text: chip.task.detail ? String(chip.task.detail) : ""
                font.family: Theme.sans
                font.pixelSize: Theme.fs(11.5)
                color: Theme.surface
                renderType: Text.NativeRendering
            }
        }
    }

    BarButton {
        visible: chip.caps.pause === true && chip.taskState === "running"
        glyph: "\u{f03e4}"
        tooltip: I18n.tr("Pause")
        hpad: 7
        onTriggered: Tasks.control(chip.taskId, "pause")
    }
    BarButton {
        visible: chip.caps.resume === true && chip.taskState === "paused"
        glyph: "\u{f040a}"
        tooltip: I18n.tr("Resume")
        hpad: 7
        onTriggered: Tasks.control(chip.taskId, "resume")
    }
    BarButton {
        visible: chip.caps.stop === true
        glyph: "\u{f04db}"
        tooltip: I18n.tr("Stop")
        destructive: true
        hpad: 7
        onTriggered: Tasks.control(chip.taskId, "stop")
    }
}
