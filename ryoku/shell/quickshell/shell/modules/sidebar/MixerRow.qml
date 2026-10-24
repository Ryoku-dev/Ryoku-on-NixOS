pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property real s
    required property var node
    property bool capture: false
    property bool device: false
    readonly property var audio: node ? node.audio : null
    readonly property bool muted: !!(audio && audio.muted)
    readonly property string title: device ? Audio.nodeLabel(node) : Audio.streamName(node)
    readonly property string iconSource: device ? "" : Audio.streamIcon(node)
    readonly property string initial: title.length > 0 ? title.charAt(0).toUpperCase() : "•"
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce

    implicitHeight: 34 * s
    height: implicitHeight
    enabled: audio !== null
    opacity: enabled ? 1 : 0.48

    function setLevel(value): void {
        if (root.audio)
            root.audio.volume = Math.max(0, Math.min(1, value));
    }

    Row {
        id: row
        anchors.fill: parent
        spacing: Tokens.s2 * root.s
        readonly property real fixedWidth: avatar.width + percent.width + muteButton.width + spacing * 4
        readonly property real flexibleWidth: Math.max(0, width - fixedWidth)

        Rectangle {
            id: avatar
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.ctlH * root.s
            height: width
            radius: Tokens.radius * root.s
            color: Tokens.tint5
            border.width: Tokens.border
            border.color: Tokens.lineSoft

            Image {
                id: appIcon
                anchors.centerIn: parent
                width: Tokens.fRow * root.s
                height: width
                source: root.iconSource
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                visible: !root.device && status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !appIcon.visible
                text: root.device ? Audio.nodeIcon(root.node) : root.initial
                color: Tokens.inkDim
                font.family: root.device ? "Material Symbols Rounded" : Tokens.ui
                font.pixelSize: Tokens.fSmall * root.s
                font.weight: Font.DemiBold
                Accessible.ignored: true
            }
        }

        Text {
            id: nameLabel
            anchors.verticalCenter: parent.verticalCenter
            width: row.flexibleWidth * 0.42
            text: root.title
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall * root.s
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        QQC.Slider {
            id: slider
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, row.flexibleWidth - nameLabel.width)
            height: Tokens.ctlH * root.s
            from: 0
            to: 1
            stepSize: 0.01
            snapMode: QQC.Slider.SnapAlways
            value: root.audio ? root.audio.volume : 0
            Accessible.name: I18n.tr("%1 volume").arg(root.title)
            onMoved: root.setLevel(value)
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: Tokens.s1 * root.s
                radius: height / 2
                color: Tokens.tint10
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: root.muted ? Tokens.inkFaint : Tokens.bone
                    Behavior on width {
                        enabled: root.motionAllowed && !slider.pressed
                        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                    }
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: Tokens.s3 * root.s
                height: width
                radius: width / 2
                color: root.muted ? Tokens.inkFaint : Tokens.bone
                border.width: Tokens.border
                border.color: Tokens.paper
                scale: slider.pressed ? 1.22 : slider.hovered || slider.visualFocus ? 1.1 : 1
                Behavior on scale {
                    enabled: root.motionAllowed
                    NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
            WheelHandler {
                onWheel: event => {
                    const direction = event.angleDelta.y >= 0 ? 1 : -1;
                    root.setLevel(slider.value + direction * 0.02);
                    event.accepted = true;
                }
            }
        }

        Text {
            id: percent
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.s7 * root.s
            text: Math.round((root.audio ? root.audio.volume : 0) * 100) + "%"
            color: root.muted ? Tokens.inkFaint : Tokens.inkDim
            font.family: Tokens.mono
            font.pixelSize: Tokens.fTiny * root.s
            horizontalAlignment: Text.AlignRight
        }

        QQC.AbstractButton {
            id: muteButton
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.ctlH * root.s
            height: width
            hoverEnabled: true
            Accessible.name: root.muted ? I18n.tr("Unmute %1").arg(root.title) : I18n.tr("Mute %1").arg(root.title)
            onClicked: if (root.audio) root.audio.muted = !root.audio.muted
            background: Rectangle {
                radius: Tokens.radius * root.s
                color: root.muted ? Tokens.bone : muteButton.down ? Tokens.tint16 : muteButton.hovered ? Tokens.tint10 : "transparent"
                border.width: root.muted || muteButton.visualFocus ? Tokens.border : 0
                border.color: root.muted ? Tokens.bone : Tokens.lineSoft
                Behavior on color {
                    enabled: root.motionAllowed
                    ColorAnimation { duration: Tokens.snap }
                }
            }
            contentItem: Text {
                text: root.capture ? (root.muted ? "mic_off" : "mic") : (root.muted ? "volume_off" : "volume_up")
                color: root.muted ? Tokens.inkOnBone : Tokens.inkDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: Tokens.fSmall * root.s
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Accessible.ignored: true
            }
            scale: down ? 0.9 : 1
            Behavior on scale {
                enabled: root.motionAllowed
                NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
            }
            HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
    }
}