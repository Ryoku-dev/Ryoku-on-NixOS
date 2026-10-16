pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    property string query: ""
    signal navigate(string section)
    signal requestClose()

    property bool awaitingToast: false
    property int toastFloor: -1
    property string shownToast: ""
    property bool toastVisible: false
    property bool toastError: false
    property string composer: ""
    readonly property var device: client.activeDevice
    readonly property var plugins: device && Array.isArray(device.plugins) ? device.plugins : []
    readonly property bool reachable: device && device.reachable === true
    readonly property var callState: client.state.call || ({ state: "idle" })
    readonly property var adb: client.state.adb || ({ state: "none" })
    readonly property var alarm: client.state.alarm || ({ nextAt: 0 })
    readonly property var commands: Array.isArray(client.state.runCommands) ? client.state.runCommands : []
    readonly property var recentNotifications: {
        const source = client.notifications.filter(function(item) {
            if (!root.query)
                return true;
            const haystack = [item.app, item.title, item.body].join(" ").toLowerCase();
            return haystack.indexOf(root.query) >= 0;
        });
        return source.slice().sort(function(a, b) { return Number(b.time || 0) - Number(a.time || 0); }).slice(0, 3);
    }

    function hasPlugin(name) {
        return root.plugins.indexOf(name) >= 0;
    }

    function reason(plugin) {
        if (!root.reachable)
            return I18n.tr("Phone is not connected");
        if (plugin && !root.hasPlugin(plugin))
            return I18n.tr("Unavailable on this phone");
        return "";
    }

    function perform(fn, args) {
        root.toastFloor = Number((root.client.state.toast || {}).seq || 0);
        root.awaitingToast = true;
        root.client.call(fn, args || [], function(ok, error) {
            if (!ok && error)
                root.showToast(error, true);
        });
    }

    function showToast(text, error) {
        root.awaitingToast = false;
        root.shownToast = String(text || "");
        root.toastError = error === true;
        root.toastVisible = root.shownToast.length > 0;
        toastTimer.restart();
    }

    function updateToast() {
        if (!root.awaitingToast)
            return;
        const toast = root.client.state.toast || {};
        const seq = Number(toast.seq || 0);
        if (seq <= root.toastFloor || !String(toast.text || ""))
            return;
        root.awaitingToast = false;
        root.showToast(String(toast.text), toast.error === true);
    }

    function alarmTime(value) {
        const date = new Date(Number(value));
        if (!isFinite(date.getTime()))
            return "";
        return Qt.formatTime(date, "HH:mm");
    }

    function activate() {
        ringTile.forceActiveFocus();
    }

    function handleEscape() {
        if (root.composer) {
            root.composer = "";
            composerField.clear();
            root.forceActiveFocus();
            return true;
        }
        return false;
    }

    function openComposer(kind) {
        root.composer = kind;
        composerField.clear();
        Qt.callLater(composerField.grabFocus);
    }

    function sendComposer() {
        const value = composerField.text.trim();
        if (!value)
            return;
        root.perform(root.composer === "share" ? "share" : "typeText", [value]);
        composerField.clear();
        root.composer = "";
    }

    Connections {
        target: root.client
        function onStateChanged() { root.updateToast(); }
    }

    Timer {
        id: toastTimer
        interval: 3200
        onTriggered: {
            root.toastVisible = false;
            clearToast.restart();
        }
    }
    Timer {
        id: clearToast
        interval: Math.max(1, Tokens.durSmall)
        onTriggered: root.shownToast = ""
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: content.implicitHeight + Tokens.s4
        ScrollBar.vertical: ScrollRail {
            policy: ScrollBar.AsNeeded
            visible: scroll.contentHeight > scroll.height + 1
        }
        WheelScroll { }

        Column {
            id: content
            width: scroll.width - Tokens.s3
            spacing: Tokens.s4

            Rectangle {
                visible: String(root.callState.state || "idle") !== "idle"
                width: parent.width
                implicitHeight: callBody.implicitHeight + Tokens.s4 * 2
                radius: Tokens.radius
                color: Tokens.paperLift
                border.width: Tokens.border
                border.color: Tokens.lineStrong
                Row {
                    id: callBody
                    anchors.fill: parent
                    anchors.margins: Tokens.s4
                    spacing: Tokens.s3
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - callActions.width - parent.spacing)
                        Text {
                            width: parent.width
                            text: String(root.callState.name || root.callState.number || I18n.tr("Incoming call"))
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fRow
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            text: String(root.callState.state || "") === "ringing"
                                ? I18n.tr("Incoming call") : I18n.tr("Call in progress")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                        }
                    }
                    Row {
                        id: callActions
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s1
                        Btn { compact: true; text: I18n.tr("SILENCE"); onAct: root.perform("callSilence", []) }
                        Btn { compact: true; text: I18n.tr("DECLINE"); onAct: root.perform("callDecline", []) }
                        Btn { compact: true; primary: true; text: I18n.tr("ANSWER"); onAct: root.perform("callAnswer", []) }
                    }
                }
            }
            Grid {
                id: actions
                width: parent.width
                columns: root.hasPlugin("kdeconnect_remotekeyboard") ? 4 : 3
                readonly property real tileWidth: (width - columnSpacing * (columns - 1)) / columns
                columnSpacing: Tokens.s3
                rowSpacing: Tokens.s3

                PhoneActionTile {
                    id: ringTile
                    width: actions.tileWidth
                    glyph: "notifications_active"
                    label: I18n.tr("Ring")
                    detail: root.reason("kdeconnect_findmyphone") || I18n.tr("Find your phone")
                    armed: root.reason("kdeconnect_findmyphone").length === 0
                    onAct: root.perform("ring", [])
                }
                PhoneActionTile {
                    width: actions.tileWidth
                    glyph: "upload_file"
                    label: I18n.tr("Send files")
                    detail: root.reason("kdeconnect_share") || I18n.tr("Choose files to send")
                    armed: root.reason("kdeconnect_share").length === 0
                    onAct: {
                        root.perform("pickFiles", []);
                        root.requestClose();
                    }
                }
                PhoneActionTile {
                    width: actions.tileWidth
                    glyph: "content_paste"
                    label: I18n.tr("Send clipboard")
                    detail: root.reason("kdeconnect_clipboard") || I18n.tr("Share what you copied")
                    armed: root.reason("kdeconnect_clipboard").length === 0
                    onAct: root.perform("sendClipboard", [])
                }
                PhoneActionTile {
                    width: actions.tileWidth
                    glyph: "link"
                    label: I18n.tr("Share link")
                    detail: root.reason("kdeconnect_share") || I18n.tr("Send a link or short note")
                    armed: root.reason("kdeconnect_share").length === 0
                    onAct: root.openComposer("share")
                }
                PhoneActionTile {
                    width: actions.tileWidth
                    glyph: "folder_shared"
                    label: I18n.tr("Browse files")
                    detail: root.reason("kdeconnect_sftp") || I18n.tr("Open phone storage")
                    armed: root.reason("kdeconnect_sftp").length === 0
                    onAct: {
                        root.perform("browse", []);
                        root.requestClose();
                    }
                }
                PhoneActionTile {
                    width: actions.tileWidth
                    glyph: "vibration"
                    label: I18n.tr("Ping")
                    detail: root.reason("kdeconnect_ping") || I18n.tr("Send a quick signal")
                    armed: root.reason("kdeconnect_ping").length === 0
                    onAct: root.perform("ping", [])
                }
                PhoneActionTile {
                    visible: root.hasPlugin("kdeconnect_remotekeyboard")
                    width: visible ? actions.tileWidth : 0
                    glyph: "keyboard"
                    label: I18n.tr("Type on phone")
                    detail: root.reason("kdeconnect_remotekeyboard") || I18n.tr("Send text as keyboard input")
                    armed: root.reason("kdeconnect_remotekeyboard").length === 0
                    onAct: root.openComposer("type")
                }
            }

            Rectangle {
                visible: height > 0
                width: parent.width
                height: root.composer ? composerRow.implicitHeight + Tokens.s3 * 2 : 0
                opacity: root.composer ? 1 : 0
                clip: true
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
                Row {
                    id: composerRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.s3
                    spacing: Tokens.s2
                    Field {
                        id: composerField
                        width: parent.width - sendComposer.width - parent.spacing
                        placeholder: root.composer === "type"
                            ? I18n.tr("Text to type on your phone") : I18n.tr("Link or text to share")
                        onAccepted: root.sendComposer()
                    }
                    Btn {
                        id: sendComposer
                        primary: true
                        text: root.composer === "type" ? I18n.tr("TYPE") : I18n.tr("SEND")
                        armed: composerField.text.trim().length > 0
                        onAct: root.sendComposer()
                    }
                }
            }

            Text {
                width: parent.width
                height: root.shownToast ? implicitHeight : 0
                opacity: root.toastVisible ? 1 : 0
                visible: root.shownToast.length > 0
                text: root.shownToast
                color: root.toastError ? Tokens.alert : Tokens.inkDim
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
                Behavior on opacity {
                    enabled: !Tokens.reduceMotion
                    NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                }
            }

            Rectangle {
                visible: root.adb.state !== "device"
                width: parent.width
                implicitHeight: mirrorRow.implicitHeight + Tokens.s4 * 2
                radius: Tokens.radius
                color: Tokens.paperLift
                border.width: Tokens.border
                border.color: Tokens.lineSoft
                Row {
                    id: mirrorRow
                    anchors.fill: parent
                    anchors.margins: Tokens.s4
                    spacing: Tokens.s3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "screen_share"
                        color: Tokens.inkDim
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: Tokens.fValue
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - setupButton.width - Tokens.s7 - parent.spacing * 2)
                        Text {
                            width: parent.width
                            text: I18n.tr("Mirror your screen, use its camera and mic")
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            font.weight: Font.DemiBold
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            width: parent.width
                            text: I18n.tr("Needs USB debugging")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fTiny
                        }
                    }
                    Btn {
                        id: setupButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("SET UP")
                        primary: true
                        onAct: root.navigate("screen")
                    }
                }
            }


            Rectangle {
                visible: Number(root.alarm.nextAt || 0) > 0
                width: parent.width
                implicitHeight: Tokens.rowH + Tokens.s3
                radius: Tokens.radius
                color: Tokens.paperLift
                border.width: Tokens.border
                border.color: Tokens.lineSoft
                Row {
                    anchors.fill: parent
                    anchors.margins: Tokens.s3
                    spacing: Tokens.s3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "alarm"
                        color: Tokens.inkDim
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: Tokens.fBody
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Next alarm %1").arg(root.alarmTime(root.alarm.nextAt))
                        color: Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        font.weight: Font.DemiBold
                    }
                }
            }

            Column {
                visible: root.commands.length > 0
                width: parent.width
                spacing: Tokens.s2
                Text {
                    text: I18n.tr("PHONE COMMANDS")
                    color: Tokens.inkMuted
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                    font.letterSpacing: Tokens.trackLabel
                }
                Flow {
                    width: parent.width
                    spacing: Tokens.s2
                    Repeater {
                        model: root.commands
                        delegate: Btn {
                            required property var modelData
                            text: String(modelData.name || I18n.tr("Run command")).toUpperCase()
                            onAct: root.perform("runCommand", [String(modelData.id || "")])
                        }
                    }
                }
            }

            Column {
                visible: root.recentNotifications.length > 0
                width: parent.width
                spacing: Tokens.s2
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - seeAll.width
                        text: I18n.tr("RECENT NOTIFICATIONS")
                        color: Tokens.inkMuted
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fMicro
                        font.letterSpacing: Tokens.trackLabel
                    }
                    Btn {
                        id: seeAll
                        compact: true
                        text: I18n.tr("SEE ALL")
                        onAct: root.navigate("notifications")
                    }
                }
                Repeater {
                    model: root.recentNotifications
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        implicitHeight: recentBody.implicitHeight + Tokens.s3 * 2
                        radius: Tokens.radius
                        color: Tokens.paperLift
                        border.width: Tokens.border
                        border.color: Tokens.lineSoft
                        Column {
                            id: recentBody
                            anchors.fill: parent
                            anchors.margins: Tokens.s3
                            spacing: Tokens.s1
                            Text {
                                width: parent.width
                                text: String(parent.parent.modelData.app || I18n.tr("Phone"))
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fTiny
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: String(parent.parent.modelData.title || parent.parent.modelData.body || I18n.tr("Notification"))
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
