pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

Column {
    id: root

    required property var client
    readonly property var requests: {
        const pairing = root.client && root.client.state ? root.client.state.pairing : null;
        return pairing && Array.isArray(pairing.incoming) ? pairing.incoming : [];
    }

    width: parent ? parent.width : implicitWidth
    spacing: Tokens.s2
    visible: requests.length > 0

    Repeater {
        model: root.requests
        delegate: Rectangle {
            id: banner
            required property var modelData
            required property int index
            property bool entered: Tokens.reduceMotion

            width: root.width
            implicitHeight: row.implicitHeight + Tokens.s3 * 2
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineStrong
            opacity: entered ? 1 : 0
            transform: Translate { y: banner.entered ? 0 : Tokens.s2 }

            Component.onCompleted: delay.start()
            Timer {
                id: delay
                interval: Tokens.reduceMotion ? 0 : Math.min(banner.index, 5) * 28
                onTriggered: banner.entered = true
            }
            Behavior on opacity {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
            }

            Row {
                id: row
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.s3
                spacing: Tokens.s3

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "phonelink_ring"
                    color: Tokens.inkDim
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: Tokens.fValue
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(0, row.width - actions.width - Tokens.s7 - row.spacing * 2)
                    spacing: Tokens.s1
                    Text {
                        width: parent.width
                        text: I18n.tr("Pairing request")
                        color: Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("%1 wants to connect").arg(String(banner.modelData.name || I18n.tr("A phone")))
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: actions
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.s1
                    Btn {
                        compact: true
                        text: I18n.tr("DECLINE")
                        onAct: root.client.call("rejectPair", [String(banner.modelData.id || "")])
                    }
                    Btn {
                        compact: true
                        primary: true
                        text: I18n.tr("ACCEPT")
                        onAct: root.client.call("acceptPair", [String(banner.modelData.id || "")])
                    }
                }
            }
        }
    }
}
