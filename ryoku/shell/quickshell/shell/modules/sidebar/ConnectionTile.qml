pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root
    required property bool active

    required property real s
    required property string label
    required property string detail
    required property string glyph
    required property string kind
    property bool connected: false
    property bool radioOn: false
    property bool available: true
    property real strength: 0
    property int connectedCount: 0
    signal selected()
    signal toggleRequested()

    readonly property bool motionAllowed: root.active && !Tokens.reduceMotion && !Motion.reduce
    readonly property int litBars: !root.connected || !root.radioOn || root.strength <= 0
        ? 0 : Math.max(1, Math.min(4, Math.ceil(root.strength * 4)))

    implicitHeight: (Tokens.rowH + Tokens.s3) * s
    opacity: available ? 1 : 0.52
    scale: body.down || radio.down ? 0.985 : 1
    transformOrigin: Item.Center

    Behavior on scale {
        enabled: root.motionAllowed
        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: Tokens.radius * root.s * 1.5
        color: root.connected ? Tokens.bone : body.hovered ? Tokens.tint10 : Tokens.paperLift
        border.width: Tokens.border
        border.color: root.connected ? Tokens.bone : body.visualFocus ? Tokens.lineStrong : Tokens.lineSoft

        Behavior on color {
            enabled: root.motionAllowed
            ColorAnimation { duration: Tokens.snap }
        }
        Behavior on border.color {
            enabled: root.motionAllowed
            ColorAnimation { duration: Tokens.snap }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Tokens.tint10
            opacity: root.connected && body.hovered ? 1 : 0

            Behavior on opacity {
                enabled: root.motionAllowed
                NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
            }
        }
    }

    QQC.AbstractButton {
        id: body
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.available
        Accessible.name: root.label
        Accessible.description: root.detail
        onClicked: root.selected()
        background: Item {}

        contentItem: Item {
            Text {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: Tokens.s3 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: (Tokens.s5 - Tokens.s1) * root.s
                height: width
                text: root.glyph
                color: root.connected ? Tokens.inkOnBone : Tokens.inkDim
                font.family: "Material Symbols Rounded"
                font.pixelSize: (Tokens.s5 - Tokens.s1) * root.s
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                Accessible.ignored: true

                Behavior on color {
                    enabled: root.motionAllowed
                    ColorAnimation { duration: Tokens.snap }
                }
            }

            Column {
                anchors.left: icon.right
                anchors.leftMargin: Tokens.s2 * root.s
                anchors.right: indicator.left
                anchors.rightMargin: Tokens.s2 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.s1 * root.s

                Text {
                    width: parent.width
                    text: root.label
                    color: root.connected ? Tokens.inkOnBone : Tokens.ink
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fRow * root.s
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight

                    Behavior on color {
                        enabled: root.motionAllowed
                        ColorAnimation { duration: Tokens.snap }
                    }
                }

                Text {
                    width: parent.width
                    text: root.detail
                    color: root.connected ? Tokens.inkOnBone : Tokens.inkMuted
                    opacity: root.connected ? 0.74 : 1
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall * root.s
                    elide: Text.ElideRight

                    Behavior on color {
                        enabled: root.motionAllowed
                        ColorAnimation { duration: Tokens.snap }
                    }
                    Behavior on opacity {
                        enabled: root.motionAllowed
                        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                    }
                }
            }

            Item {
                id: indicator
                anchors.right: parent.right
                anchors.rightMargin: radio.width + (Tokens.s3 + Tokens.s2) * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: root.kind === "wifi" ? signalRow.implicitWidth
                    : root.kind === "bluetooth" && root.connectedCount > 0 ? badge.implicitWidth : 0
                height: (Tokens.s5 - Tokens.s1) * root.s

                Row {
                    id: signalRow
                    visible: root.kind === "wifi"
                    anchors.centerIn: parent
                    spacing: Tokens.s1 * root.s / 2

                    Repeater {
                        model: 4

                        delegate: Item {
                            id: signalSlot
                            required property int index
                            width: Tokens.s1 * root.s / 2
                            height: (Tokens.s3 - Tokens.s1 / 2) * root.s

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: (Tokens.s1 + signalSlot.index * Tokens.s1 / 2) * root.s
                                radius: width / 2
                                color: root.connected ? Tokens.inkOnBone : Tokens.inkDim
                                opacity: root.radioOn && signalSlot.index < root.litBars ? 1 : 0.22

                                Behavior on opacity {
                                    enabled: root.motionAllowed
                                    SequentialAnimation {
                                        PauseAnimation { duration: signalSlot.index * Tokens.snap / 3 }
                                        NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease }
                                    }
                                }
                                Behavior on color {
                                    enabled: root.motionAllowed
                                    ColorAnimation { duration: Tokens.snap }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: badge
                    visible: root.kind === "bluetooth" && root.connectedCount > 0
                    anchors.centerIn: parent
                    implicitWidth: Math.max(
                        (Tokens.s5 - Tokens.s1) * root.s,
                        countLabel.implicitWidth + Tokens.s2 * root.s
                    )
                    width: implicitWidth
                    height: (Tokens.s5 - Tokens.s1) * root.s
                    radius: height / 2
                    color: root.connected ? Tokens.inkOnBone : Tokens.tint10
                    border.width: Tokens.border
                    border.color: root.connected ? Tokens.inkOnBone : Tokens.line

                    Behavior on color {
                        enabled: root.motionAllowed
                        ColorAnimation { duration: Tokens.snap }
                    }
                    Behavior on border.color {
                        enabled: root.motionAllowed
                        ColorAnimation { duration: Tokens.snap }
                    }

                    Text {
                        id: countLabel
                        anchors.centerIn: parent
                        text: String(root.connectedCount)
                        color: root.connected ? Tokens.bone : Tokens.inkDim
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fTiny * root.s
                        font.weight: Font.DemiBold

                        Behavior on color {
                            enabled: root.motionAllowed
                            ColorAnimation { duration: Tokens.snap }
                        }
                    }
                }
            }
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    QQC.AbstractButton {
        id: radio
        anchors.right: parent.right
        anchors.rightMargin: Tokens.s3 * root.s
        anchors.verticalCenter: parent.verticalCenter
        width: (Tokens.s6 + Tokens.s1 / 2) * root.s
        height: (Tokens.s5 - Tokens.s1) * root.s
        hoverEnabled: true
        enabled: root.available
        Accessible.role: Accessible.CheckBox
        Accessible.name: root.radioOn ? I18n.tr("Turn off %1").arg(root.label) : I18n.tr("Turn on %1").arg(root.label)
        Accessible.checkable: true
        Accessible.checked: root.radioOn
        onClicked: root.toggleRequested()

        background: Rectangle {
            id: switchTrack
            radius: height / 2
            color: radio.down ? (root.connected ? Tokens.inkOnBone : Tokens.tint16)
                : root.radioOn ? (root.connected ? Tokens.inkOnBone : Tokens.bone) : Tokens.tint16
            border.width: Tokens.border
            border.color: radio.visualFocus ? (root.connected ? Tokens.inkOnBone : Tokens.bone)
                : root.radioOn ? (root.connected ? Tokens.inkOnBone : Tokens.bone) : Tokens.lineStrong

            Behavior on color {
                enabled: root.motionAllowed
                ColorAnimation { duration: Tokens.move; easing.type: Tokens.ease }
            }
            Behavior on border.color {
                enabled: root.motionAllowed
                ColorAnimation { duration: Tokens.move; easing.type: Tokens.ease }
            }

            Rectangle {
                width: (Tokens.s4 - Tokens.s1 / 2) * root.s
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: root.radioOn ? parent.width - width - Tokens.radius * root.s / 2
                    : Tokens.radius * root.s / 2
                color: root.radioOn ? (root.connected ? Tokens.bone : Tokens.inkOnBone) : Tokens.inkDim

                Behavior on x {
                    enabled: root.motionAllowed
                    NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease }
                }
                Behavior on color {
                    enabled: root.motionAllowed
                    ColorAnimation { duration: Tokens.move; easing.type: Tokens.ease }
                }
            }
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }
}