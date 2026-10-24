pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property real s
    property string mode: "ask"
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce
    readonly property var modes: [
        { id: "ask", label: I18n.tr("Ask"), hint: "\\" },
        { id: "chat", label: I18n.tr("Agent"), hint: "" },
        { id: "tools", label: I18n.tr("Tools"), hint: "/" },
        { id: "web", label: I18n.tr("Web"), hint: "?" }
    ]
    readonly property int currentIndex: Math.max(0, modes.findIndex(item => item.id === mode))

    signal modeRequested(string mode)

    implicitHeight: 38 * s

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius * root.s
        color: Tokens.paperLift
        border.width: Tokens.border
        border.color: Tokens.lineSoft
    }

    Rectangle {
        id: selection
        x: root.currentIndex * root.width / root.modes.length
        width: root.width / root.modes.length
        height: parent.height
        radius: Tokens.radius * root.s
        color: Tokens.bone
        Behavior on x {
            enabled: root.motionAllowed
            NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease }
        }
    }

    Row {
        anchors.fill: parent
        Repeater {
            model: root.modes
            delegate: Item {
                id: modeCell
                required property var modelData
                required property int index
                width: root.width / root.modes.length
                height: root.height
                scale: modeTap.pressed && root.motionAllowed ? 0.96
                    : modeHover.hovered && root.motionAllowed ? 0.985 : 1
                Behavior on scale {
                    enabled: root.motionAllowed
                    NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radius * root.s
                    color: modeCell.index === root.currentIndex ? "transparent"
                        : modeTap.pressed ? Tokens.tint16
                        : modeHover.hovered ? Tokens.tint10 : "transparent"
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Tokens.s2 * root.s
                    Text {
                        text: modeCell.modelData.label
                        color: modeCell.index === root.currentIndex ? Tokens.inkOnBone : Tokens.inkDim
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall * root.s
                        font.weight: modeCell.index === root.currentIndex ? Font.DemiBold : Font.Normal
                    }
                    Rectangle {
                        visible: modeCell.modelData.hint.length > 0
                        width: hintText.implicitWidth + Tokens.s2 * root.s
                        height: 20 * root.s
                        radius: Tokens.radius * root.s
                        color: Tokens.tint5
                        Text {
                            id: hintText
                            anchors.centerIn: parent
                            text: modeCell.modelData.hint
                            color: Tokens.inkFaint
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fTiny * root.s
                        }
                    }
                }
                HoverHandler { id: modeHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: modeTap; onTapped: root.modeRequested(modeCell.modelData.id) }
            }
        }
    }
}
