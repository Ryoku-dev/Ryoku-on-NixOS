pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var option
    property int entranceIndex: 0
    property var value
    signal changed(var value)
    property real reveal: 1

    opacity: reveal
    transform: Translate { x: (1 - root.reveal) * 6 }

    implicitHeight: label.implicitHeight + Tokens.s2 + Math.max(textField.visible ? textField.implicitHeight : 0,
        toggle.visible ? toggle.implicitHeight : 0, choices.visible ? choices.implicitHeight : 0)
    Component.onCompleted: {
        if (!Tokens.reduceMotion) {
            reveal = 0;
            entrance.start();
        }
    }

    SequentialAnimation {
        id: entrance
        PauseAnimation { duration: Math.min(120, root.entranceIndex * 24) }
        NumberAnimation {
            target: root
            property: "reveal"
            from: 0
            to: 1
            duration: Tokens.durSmall
            easing.type: Easing.OutCubic
        }
    }

    Text {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        text: root.option.label ?? root.option.id
        color: Tokens.inkMuted
        font.family: Tokens.ui
        font.pixelSize: Tokens.fSmall
    }

    Field {
        id: textField
        anchors.top: label.bottom
        anchors.topMargin: Tokens.s2
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.option.type === "text"
        tabular: true
        text: visible ? String(root.value ?? "") : ""
        onEdited: value => root.changed(value)
    }

    Sw {
        id: toggle
        anchors.top: label.bottom
        anchors.topMargin: Tokens.s2
        anchors.left: parent.left
        visible: root.option.type === "toggle"
        on: Boolean(root.value)
        onToggled: value => root.changed(value)
    }

    Flow {
        id: choices
        anchors.top: label.bottom
        anchors.topMargin: Tokens.s2
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.s1
        visible: root.option.type === "choice"

        Repeater {
            model: root.option.choices ?? []
            delegate: Rectangle {
                id: choice
                required property var modelData
                readonly property bool selected: String(root.value) === String(modelData.value)
                scale: tap.pressed ? 0.97 : 1
                width: choiceLabel.implicitWidth + Tokens.s4
                height: 24
                radius: Tokens.radius
                color: selected ? Tokens.bone : (tap.pressed ? Tokens.tint16 : (hover.hovered ? Tokens.tint10 : "transparent"))
                border.width: Tokens.border
                border.color: selected ? Tokens.bone : (hover.hovered ? Tokens.lineStrong : Tokens.line)
                Behavior on color {
                    enabled: !Tokens.reduceMotion
                    ColorAnimation { duration: Tokens.snap }
                }
                Behavior on border.color {
                    enabled: !Tokens.reduceMotion
                    ColorAnimation { duration: Tokens.snap }
                }
                Behavior on scale {
                    enabled: !Tokens.reduceMotion
                    NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                }

                Text {
                    id: choiceLabel
                    anchors.centerIn: parent
                    text: String(choice.modelData.label ?? choice.modelData.value)
                    color: choice.selected ? Tokens.inkOnBone : Tokens.inkDim
                    Behavior on color {
                        enabled: !Tokens.reduceMotion
                        ColorAnimation { duration: Tokens.snap }
                    }
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fTiny
                    font.weight: Font.Medium
                }
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: tap; onTapped: root.changed(choice.modelData.value) }
            }
        }
    }
}
