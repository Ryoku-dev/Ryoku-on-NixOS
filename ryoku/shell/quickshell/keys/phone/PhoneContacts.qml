pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    property string query: ""

    readonly property bool adbReady: String((client.state.adb || {}).state || "none") === "device"
    readonly property var filtered: {
        const source = client.contacts.filter(function(contact) {
            if (!root.query)
                return true;
            const numbers = root.contactNumbers(contact)
                .map(item => item.number).join(" ");
            return (String(contact.name || "") + " " + numbers).toLowerCase().indexOf(root.query) >= 0;
        });
        return source.slice().sort(function(a, b) {
            if ((a.favorite === true) !== (b.favorite === true))
                return a.favorite === true ? -1 : 1;
            return String(a.name || "").localeCompare(String(b.name || ""));
        });
    }

    function contactNumbers(contact) {
        const source = contact && contact.numbers ? contact.numbers : [];
        const result = [];
        for (let i = 0; i < Number(source.length || 0); i++) {
            const number = String(source[i].number || "");
            if (number)
                result.push({ number: number, type: String(source[i].type || "") });
        }
        return result;
    }

    function avatarSource(path) {
        const value = String(path || "");
        return value.startsWith("/") ? "file://" + value : value;
    }

    function activate() {
        refresh.forceActiveFocus();
    }

    function handleEscape() {
        return false;
    }

    Column {
        anchors.fill: parent
        spacing: Tokens.s3

        Row {
            width: parent.width
            height: Tokens.s6
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - refresh.width
                text: root.filtered.length === 0 ? I18n.tr("Contacts")
                    : root.filtered.length === 1 ? I18n.tr("1 contact - favourites first")
                    : I18n.tr("%1 contacts - favourites first").arg(root.filtered.length)
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                elide: Text.ElideRight
            }
            Btn {
                id: refresh
                compact: true
                text: I18n.tr("REFRESH")
                onAct: root.client.call("contactsRefresh", [])
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - Tokens.s6 - parent.spacing
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            spacing: Tokens.s2
            model: root.filtered
            ScrollBar.vertical: ScrollRail {
                policy: ScrollBar.AsNeeded
                visible: list.contentHeight > list.height + 1
            }
            WheelScroll { }

            delegate: Rectangle {
                id: contact
                required property var modelData
                required property int index
                property bool entered: Tokens.reduceMotion
                property int numberIndex: 0
                readonly property var phoneNumbers: root.contactNumbers(contact.modelData)
                readonly property string currentNumber: phoneNumbers.length > numberIndex
                    ? String(phoneNumbers[numberIndex].number || "") : ""
                width: list.width - Tokens.s3
                implicitHeight: Math.max(Tokens.rowH + Tokens.s3, row.implicitHeight + Tokens.s3 * 2)
                radius: Tokens.radius
                color: Tokens.paperLift
                border.width: Tokens.border
                border.color: modelData.favorite === true ? Tokens.lineStrong : Tokens.lineSoft
                opacity: entered ? 1 : 0
                transform: Translate { y: contact.entered ? 0 : Tokens.s2 }
                Component.onCompleted: delay.start()
                Timer {
                    id: delay
                    interval: Tokens.reduceMotion ? 0 : Math.min(contact.index, 8) * 24
                    onTriggered: contact.entered = true
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

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Tokens.s7
                        height: width
                        radius: width / 2
                        color: Tokens.tint10
                        clip: true
                        Image {
                            id: avatar
                            anchors.fill: parent
                            source: root.avatarSource(contact.modelData.avatar)
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                        }
                        Text {
                            visible: avatar.status !== Image.Ready
                            anchors.centerIn: parent
                            text: String(contact.modelData.name || "?").slice(0, 1).toUpperCase()
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fBody
                            font.weight: Font.Bold
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, row.width - actions.width - Tokens.s7 - row.spacing * 2)
                        spacing: Tokens.s1
                        Text {
                            width: parent.width
                            text: String(contact.modelData.name || I18n.tr("Unknown contact"))
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: contact.currentNumber || I18n.tr("No phone number")
                            color: Tokens.inkMuted
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fTiny
                            elide: Text.ElideRight
                        }
                        Flow {
                            visible: contact.phoneNumbers.length > 1
                            width: parent.width
                            spacing: Tokens.s1
                            Repeater {
                                model: contact.phoneNumbers
                                delegate: Btn {
                                    required property var modelData
                                    required property int index
                                    compact: true
                                    primary: contact.numberIndex === index
                                    text: String(modelData.type || modelData.number).toUpperCase()
                                    onAct: contact.numberIndex = index
                                }
                            }
                        }
                        Text {
                            visible: !root.adbReady && contact.currentNumber.length > 0
                            width: parent.width
                            text: I18n.tr("Call and Message need USB debugging")
                            color: Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fTiny
                            elide: Text.ElideRight
                        }
                    }

                    Row {
                        id: actions
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s1
                        IconBtn {
                            glyph: contact.modelData.favorite === true ? "★" : "☆"
                            Accessible.name: I18n.tr("Favourite contact")
                            onAct: root.client.call("favoriteContact", [String(contact.modelData.id || ""), contact.modelData.favorite === true ? "false" : "true"])
                        }
                        IconBtn {
                            glyph: "⧉"
                            armed: contact.currentNumber.length > 0
                            Accessible.name: I18n.tr("Copy number")
                            onAct: Quickshell.clipboardText = contact.currentNumber
                        }
                        Btn {
                            compact: true
                            text: I18n.tr("CALL")
                            armed: root.adbReady && contact.currentNumber.length > 0
                            onAct: root.client.call("call", [contact.currentNumber])
                        }
                        Btn {
                            compact: true
                            text: I18n.tr("MESSAGE")
                            armed: root.adbReady && contact.currentNumber.length > 0
                            onAct: root.client.call("sms", [contact.currentNumber])
                        }
                    }
                }
            }

            Column {
                visible: list.count === 0
                anchors.top: parent.top
                anchors.topMargin: Tokens.s5
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: Tokens.s3
                spacing: Tokens.s3
                Text {
                    width: parent.width
                    text: root.query
                        ? I18n.tr("No contacts match this search.")
                        : I18n.tr("No contacts yet. On the phone open KDE Connect, choose this computer, and allow Contacts sync.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }
                Btn {
                    text: I18n.tr("REFRESH")
                    onAct: root.client.call("contactsRefresh", [])
                }
            }
        }
    }
}
