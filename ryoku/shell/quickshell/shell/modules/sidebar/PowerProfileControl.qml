pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons
import shell.services

Rectangle {
    id: root

    required property real s
    required property bool active

    readonly property var labels: ({
        "power-saver": "Power Saver",
        "balanced": "Balanced",
        "performance": "Performance"
    })

    implicitHeight: content.implicitHeight + Tokens.s3 * root.s * 2
    radius: Tokens.radius * root.s * 1.5
    color: Tokens.paperLift
    border.width: Tokens.border
    border.color: Tokens.lineSoft
    Accessible.name: I18n.tr("Power Profile")
    Accessible.description: I18n.tr("System-wide CPU and device policy")

    onActiveChanged: PowerProfiles.setActive(root, root.active)
    Component.onCompleted: PowerProfiles.setActive(root, root.active)
    Component.onDestruction: PowerProfiles.setActive(root, false)

    Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.s3 * root.s
        spacing: Tokens.s2 * root.s

        Item {
            width: parent.width
            height: heading.implicitHeight

            Text {
                id: heading
                anchors.left: parent.left
                anchors.right: stateLabel.left
                anchors.rightMargin: Tokens.s2 * root.s
                text: I18n.tr("Power Profile")
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fRow * root.s
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Text {
                id: stateLabel
                anchors.right: parent.right
                text: PowerProfiles.available
                    ? I18n.tr("System power")
                    : I18n.tr("Unavailable")
                color: PowerProfiles.available ? Tokens.inkMuted : Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny * root.s
                font.capitalization: Font.AllUppercase
                font.letterSpacing: Tokens.trackLabel
            }
        }

        SidebarSegments {
            width: parent.width
            visible: PowerProfiles.available
            s: root.s
            options: PowerProfiles.profiles
            labels: root.labels
            current: PowerProfiles.profile
            onChose: key => PowerProfiles.setProfile(key)
        }

        Text {
            width: parent.width
            visible: !PowerProfiles.available
            text: I18n.tr("Power profiles unavailable")
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall * root.s
            elide: Text.ElideRight
        }
    }
}
