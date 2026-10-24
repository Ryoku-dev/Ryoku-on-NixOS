pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    signal requestClose()
    property bool menuOpen: false

    readonly property var device: root.client ? root.client.activeDevice : null
    readonly property var paired: root.client ? root.client.pairedDevices : []
    readonly property string statusText: {
        if (!root.device || root.device.reachable !== true)
            return I18n.tr("Not connected · open KDE Connect on your phone");
        const parts = [I18n.tr("Connected")];
        const charge = Number(root.device.charge);
        if (charge >= 0)
            parts.push(charge + "%");
        if (root.device.charging === true)
            parts.push(I18n.tr("charging"));
        return parts.join(" · ");
    }

    implicitHeight: head.height + (menuOpen ? Tokens.s2 + menu.implicitHeight : 0)

    Row {
        id: head
        width: parent.width
        height: Tokens.s7 + Tokens.s2
        spacing: Tokens.s2

        QQC.AbstractButton {
            id: deviceButton
            width: parent.width - settings.width - parent.spacing
            height: parent.height
            hoverEnabled: root.paired.length > 1
            onClicked: if (root.paired.length > 1) root.menuOpen = !root.menuOpen
            scale: down ? 0.99 : hovered ? 1.005 : 1
            Behavior on scale {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
            }

            background: Rectangle {
                radius: Tokens.radius
                color: deviceButton.down ? Tokens.tint16
                    : deviceButton.hovered ? Tokens.tint5 : "transparent"
                border.width: root.paired.length > 1 ? Tokens.border : 0
                border.color: Tokens.lineSoft
                Behavior on color {
                    enabled: !Tokens.reduceMotion
                    ColorAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                }
            }

            contentItem: Row {
                spacing: Tokens.s3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.device && root.device.type === "tablet" ? "tablet" : "smartphone"
                    color: root.device && root.device.reachable === true ? Tokens.ink : Tokens.inkMuted
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: Tokens.fValue
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, parent.width - Tokens.s7 * 2)
                    spacing: Tokens.s1
                    Text {
                        width: parent.width
                        text: root.device ? String(root.device.name || I18n.tr("Phone")) : I18n.tr("Phone")
                        color: Tokens.ink
                        font.family: Tokens.display
                        font.pixelSize: Tokens.fValue
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.statusText
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        elide: Text.ElideRight
                    }
                }
                Text {
                    visible: root.paired.length > 1
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.menuOpen ? "expand_less" : "expand_more"
                    color: Tokens.inkMuted
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: Tokens.fBody
                }
            }
        }

        IconBtn {
            id: settings
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.s6
            height: Tokens.s6
            glyph: "⚙"
            Accessible.name: I18n.tr("Phone settings")
            onAct: {
                Spawn.run(["ryoku-shell", "hub", "open", "phone"]);
                root.requestClose();
            }
        }
    }

    Rectangle {
        id: menu
        anchors.top: head.bottom
        anchors.topMargin: Tokens.s2
        anchors.left: parent.left
        anchors.right: parent.right
        implicitHeight: choices.implicitHeight + Tokens.s2 * 2
        height: root.menuOpen ? implicitHeight : 0
        opacity: root.menuOpen ? 1 : 0
        visible: height > 0
        clip: true
        z: 4
        radius: Tokens.radius
        color: Tokens.paperLift
        border.width: Tokens.border
        border.color: Tokens.lineStrong
        Behavior on height {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
        }

        Column {
            id: choices
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.s2
            spacing: Tokens.s1

            Repeater {
                model: root.paired
                delegate: QQC.AbstractButton {
                    id: choice
                    required property var modelData
                    width: choices.width
                    height: Tokens.rowH
                    hoverEnabled: true
                    onClicked: {
                        root.client.call("selectDevice", [String(modelData.id || "")]);
                        root.menuOpen = false;
                    }
                    background: Rectangle {
                        radius: Tokens.radius
                        color: String(choice.modelData.id || "") === String(root.device ? root.device.id : "")
                            ? Tokens.bone : choice.down ? Tokens.tint16
                            : choice.hovered ? Tokens.tint10 : "transparent"
                    }
                    contentItem: Row {
                        spacing: Tokens.s2
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: choice.modelData.type === "tablet" ? "tablet" : "smartphone"
                            color: String(choice.modelData.id || "") === String(root.device ? root.device.id : "")
                                ? Tokens.inkOnBone : Tokens.inkDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: Tokens.fBody
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.max(0, parent.width - Tokens.s7)
                            Text {
                                width: parent.width
                                text: String(choice.modelData.name || I18n.tr("Phone"))
                                color: String(choice.modelData.id || "") === String(root.device ? root.device.id : "")
                                    ? Tokens.inkOnBone : Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: choice.modelData.reachable === true ? I18n.tr("Connected") : I18n.tr("Not connected")
                                color: String(choice.modelData.id || "") === String(root.device ? root.device.id : "")
                                    ? Tokens.inkOnBoneDim : Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fTiny
                            }
                        }
                    }
                }
            }
        }
    }
}
