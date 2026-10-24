pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    property string query: ""
    property string section: "overview"
    signal requestClose()
    signal navigate(string section)

    function activate() {
        if (root.client.shellDown) {
            tryAgain.forceActiveFocus();
            return;
        }
        if (!root.client.ready) {
            setup.activate();
            return;
        }
        if (root.section === "notifications")
            notifications.activate();
        else if (root.section === "screen")
            screen.activate();
        else if (root.section === "contacts")
            contacts.activate();
        else if (root.section === "apps")
            apps.activate();
        else
            overview.activate();
    }

    function handleEscape() {
        if (header.menuOpen) {
            header.menuOpen = false;
            return true;
        }
        if (!root.client.ready)
            return setup.handleEscape();
        if (root.section === "notifications")
            return notifications.handleEscape();
        if (root.section === "screen")
            return screen.handleEscape();
        if (root.section === "contacts")
            return contacts.handleEscape();
        if (root.section === "apps")
            return apps.handleEscape();
        return overview.handleEscape();
    }

    function choose(section) {
        root.navigate(section);
    }

    PhonePairBanner {
        id: pairing
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        client: root.client
        z: 10
    }

    Item {
        id: body
        anchors.top: pairing.bottom
        anchors.topMargin: pairing.visible ? Tokens.s3 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        Column {
            id: shellDown
            visible: root.client.shellDown
            anchors.centerIn: parent
            width: Math.min(620, parent.width - Tokens.s6 * 2)
            spacing: Tokens.s3
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: I18n.tr("Ryoku's shell isn't running, so your phone can't be reached.")
                color: Tokens.ink
                font.family: Tokens.display
                font.pixelSize: Tokens.fTitle
                wrapMode: Text.WordWrap
            }
            Btn {
                id: tryAgain
                anchors.horizontalCenter: parent.horizontalCenter
                primary: true
                text: I18n.tr("TRY AGAIN")
                onAct: root.client.refresh()
            }
        }

        PhoneSetup {
            id: setup
            anchors.fill: parent
            visible: !root.client.shellDown && !root.client.ready
            enabled: visible
            client: root.client
            onRequestClose: root.requestClose()
        }

        Item {
            id: readyPane
            anchors.fill: parent
            visible: !root.client.shellDown && root.client.ready
            enabled: visible

            PhonePaneHeader {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                client: root.client
                onRequestClose: root.requestClose()
            }

            Item {
                id: sections
                anchors.top: header.bottom
                anchors.topMargin: Tokens.s4
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                clip: true

                PhoneOverview {
                    id: overview
                    anchors.fill: parent
                    client: root.client
                    query: root.query
                    enabled: root.section === "overview"
                    opacity: enabled ? 1 : 0
                    z: enabled ? 1 : 0
                    transform: Translate {
                        x: overview.enabled ? 0 : -Tokens.s3
                        Behavior on x {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                    }
                    onNavigate: section => root.choose(section)
                    onRequestClose: root.requestClose()
                }

                PhoneNotifications {
                    id: notifications
                    anchors.fill: parent
                    client: root.client
                    query: root.query
                    enabled: root.section === "notifications"
                    opacity: enabled ? 1 : 0
                    z: enabled ? 1 : 0
                    transform: Translate {
                        x: notifications.enabled ? 0 : Tokens.s3
                        Behavior on x {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                    }
                }

                PhoneScreen {
                    id: screen
                    anchors.fill: parent
                    client: root.client
                    enabled: root.section === "screen"
                    opacity: enabled ? 1 : 0
                    z: enabled ? 1 : 0
                    transform: Translate {
                        x: screen.enabled ? 0 : Tokens.s3
                        Behavior on x {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                    }
                    onRequestClose: root.requestClose()
                }

                PhoneContacts {
                    id: contacts
                    anchors.fill: parent
                    client: root.client
                    query: root.query
                    enabled: root.section === "contacts"
                    opacity: enabled ? 1 : 0
                    z: enabled ? 1 : 0
                    transform: Translate {
                        x: contacts.enabled ? 0 : Tokens.s3
                        Behavior on x {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                    }
                }

                PhoneApps {
                    id: apps
                    anchors.fill: parent
                    client: root.client
                    query: root.query
                    enabled: root.section === "apps"
                    opacity: enabled ? 1 : 0
                    z: enabled ? 1 : 0
                    transform: Translate {
                        x: apps.enabled ? 0 : Tokens.s3
                        Behavior on x {
                            enabled: !Tokens.reduceMotion
                            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                        }
                    }
                    Behavior on opacity {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                    }
                    onNavigate: section => root.choose(section)
                    onRequestClose: root.requestClose()
                }
            }
        }
    }
}
