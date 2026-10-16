pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    signal requestClose()
    property bool wirelessOpen: false
    property bool pairedWireless: false
    property bool awaitingMirror: false

    readonly property var adb: client.state.adb || ({ state: "none", candidates: [] })
    readonly property var scrcpy: client.state.scrcpy || ({ installed: false, appMode: false })
    readonly property var mirror: client.state.mirror || ({ running: false, starting: false, recording: false, error: "" })
    readonly property var webcam: client.state.webcam || ({ running: false, starting: false, facing: "back", ready: false, error: "" })
    readonly property bool webcamReady: client.state.configured === true && webcam.ready === true
    readonly property var mic: client.state.mic || ({ running: false, starting: false, error: "" })
    readonly property string candidate: Array.isArray(adb.candidates) && adb.candidates.length > 0
        ? String(adb.candidates[0]) : ""

    function activate() {
        if (root.adb.state === "device")
            mirrorButton.forceActiveFocus();
        else
            checkAgain.forceActiveFocus();
    }

    function handleEscape() {
        if (addressField.focused || codeField.focused) {
            root.forceActiveFocus();
            return true;
        }
        if (root.wirelessOpen) {
            root.wirelessOpen = false;
            return true;
        }
        return false;
    }

    function startMirror() {
        root.awaitingMirror = true;
        root.client.call("mirrorStart", [], function(ok) {
            if (!ok)
                root.awaitingMirror = false;
        });
    }

    function setupAndClose() {
        root.client.call("install", []);
        root.requestClose();
    }

    function seedCandidate() {
        if (!addressField.text && root.candidate)
            addressField.text = root.candidate;
    }

    Connections {
        target: root.client
        function onStateChanged() {
            root.seedCandidate();
            if (root.awaitingMirror && root.mirror.running === true) {
                root.awaitingMirror = false;
                root.requestClose();
            }
            if (root.mirror.error)
                root.awaitingMirror = false;
        }
    }

    Component.onCompleted: root.seedCandidate()

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

            Column {
                visible: root.adb.state !== "device"
                width: parent.width
                spacing: Tokens.s4

                Text {
                    width: parent.width
                    text: I18n.tr("Mirroring, Android apps, the webcam and the microphone use Android's USB debugging. You only set this up once.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }

                Column {
                    width: parent.width
                    spacing: Tokens.s3
                    Repeater {
                        model: [
                            {
                                number: "1",
                                title: I18n.tr("Turn on Developer options"),
                                detail: I18n.tr("Settings > About phone > tap Build number seven times")
                            },
                            {
                                number: "2",
                                title: I18n.tr("Turn on USB debugging"),
                                detail: I18n.tr("Settings > System > Developer options")
                            }
                        ]
                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            spacing: Tokens.s3
                            Rectangle {
                                width: Tokens.s6
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: Tokens.border
                                border.color: Tokens.lineStrong
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData.number
                                    color: Tokens.inkDim
                                    font.family: Tokens.mono
                                    font.pixelSize: Tokens.fSmall
                                }
                            }
                            Column {
                                width: Math.max(0, parent.width - Tokens.s6 - parent.spacing)
                                spacing: Tokens.s1
                                Text {
                                    width: parent.width
                                    text: parent.parent.modelData.title
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fRow
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: parent.parent.modelData.detail
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: Tokens.s3
                        Rectangle {
                            width: Tokens.s6
                            height: width
                            radius: width / 2
                            color: root.adb.state === "device" ? Tokens.bone : "transparent"
                            border.width: Tokens.border
                            border.color: root.adb.state === "device" ? Tokens.bone : Tokens.lineStrong
                            Text {
                                anchors.centerIn: parent
                                text: root.adb.state === "device" ? "✓" : "3"
                                color: root.adb.state === "device" ? Tokens.inkOnBone : Tokens.inkDim
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fSmall
                            }
                        }
                        Column {
                            width: Math.max(0, parent.width - Tokens.s6 - parent.spacing)
                            spacing: Tokens.s2
                            Text {
                                width: parent.width
                                text: I18n.tr("Connect a USB cable")
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fRow
                                font.weight: Font.DemiBold
                            }
                            Text {
                                width: parent.width
                                text: root.adb.state === "unauthorized" ? I18n.tr("Tap Allow on your phone")
                                    : root.adb.state === "offline" ? I18n.tr("Unplug the cable and plug it back in")
                                    : root.adb.state === "device" ? I18n.tr("Phone ready")
                                    : I18n.tr("Waiting for your phone...")
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                wrapMode: Text.WordWrap
                            }
                            Btn {
                                id: checkAgain
                                text: I18n.tr("CHECK AGAIN")
                                onAct: root.client.call("adbRefresh", [])
                            }
                        }
                    }
                }

                Btn {
                    text: root.wirelessOpen ? I18n.tr("HIDE WIRELESS SETUP")
                        : I18n.tr("NO CABLE? USE WIRELESS DEBUGGING (ANDROID 11+)")
                    onAct: root.wirelessOpen = !root.wirelessOpen
                }

                Rectangle {
                    visible: height > 0
                    width: parent.width
                    height: root.wirelessOpen ? wirelessBody.implicitHeight + Tokens.s4 * 2 : 0
                    opacity: root.wirelessOpen ? 1 : 0
                    clip: true
                    radius: Tokens.radius
                    color: Tokens.paperLift
                    border.width: Tokens.border
                    border.color: Tokens.lineSoft
                    Behavior on height {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        enabled: !Tokens.reduceMotion
                        NumberAnimation { duration: Tokens.snap; easing.type: Easing.OutCubic }
                    }

                    Column {
                        id: wirelessBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.s4
                        spacing: Tokens.s2
                        Text {
                            width: parent.width
                            text: I18n.tr("On your phone: Developer options > Wireless debugging > Pair device with pairing code")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            width: parent.width
                            spacing: Tokens.s2
                            Field {
                                id: addressField
                                width: parent.width * 0.62
                                tabular: true
                                placeholder: I18n.tr("Address and port")
                            }
                            Field {
                                id: codeField
                                width: parent.width - addressField.width - parent.spacing
                                tabular: true
                                placeholder: I18n.tr("Pairing code")
                                onAccepted: pairWireless.act()
                            }
                        }
                        Row {
                            spacing: Tokens.s2
                            Btn {
                                id: pairWireless
                                text: I18n.tr("PAIR")
                                primary: !root.pairedWireless
                                armed: addressField.text.trim().length > 0 && codeField.text.trim().length > 0
                                onAct: root.client.call("adbPair", [addressField.text.trim(), codeField.text.trim()], function(ok) {
                                    root.pairedWireless = ok;
                                })
                            }
                            Btn {
                                text: I18n.tr("CONNECT")
                                primary: root.pairedWireless
                                armed: addressField.text.trim().length > 0
                                onAct: root.client.call("adbConnect", [addressField.text.trim()])
                            }
                        }
                    }
                }
            }

            Column {
                visible: root.adb.state === "device"
                width: parent.width
                spacing: Tokens.s3

                Rectangle {
                    width: parent.width
                    implicitHeight: mirrorBody.implicitHeight + Tokens.s4 * 2
                    radius: Tokens.radius
                    color: Tokens.paperLift
                    border.width: Tokens.border
                    border.color: root.mirror.running || root.mirror.starting ? Tokens.lineStrong : Tokens.lineSoft
                    Column {
                        id: mirrorBody
                        anchors.fill: parent
                        anchors.margins: Tokens.s4
                        spacing: Tokens.s3
                        Row {
                            width: parent.width
                            spacing: Tokens.s3
                            Text {
                                text: "screen_share"
                                color: Tokens.inkDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: Tokens.fValue
                            }
                            Column {
                                width: Math.max(0, parent.width - Tokens.s7)
                                Text {
                                    width: parent.width
                                    text: I18n.tr("Mirror")
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fRow
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    width: parent.width
                                    text: I18n.tr("Opens your phone in a window you can use with mouse and keyboard")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                        Text {
                            visible: String(root.mirror.error || "").length > 0
                            width: parent.width
                            text: String(root.mirror.error || "")
                            color: Tokens.alert
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            width: parent.width
                            spacing: Tokens.s3
                            Btn {
                                id: mirrorButton
                                text: root.mirror.running ? I18n.tr("STOP")
                                    : root.mirror.starting || root.awaitingMirror ? I18n.tr("STARTING...") : I18n.tr("START MIRRORING")
                                primary: !root.mirror.running
                                armed: root.mirror.running === true
                                    || (root.scrcpy.installed === true && root.mirror.starting !== true && !root.awaitingMirror)
                                onAct: root.mirror.running
                                    ? root.client.call("mirrorStop", []) : root.startMirror()
                            }
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.s2
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Record screen")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                }
                                Sw {
                                    on: root.mirror.recording === true
                                    enabled: root.scrcpy.installed === true
                                    opacity: enabled ? 1 : 0.5
                                    onToggled: value => root.client.call(value ? "recordStart" : "recordStop", [])
                                }
                            }
                            Btn {
                                visible: root.adb.wireless !== true
                                compact: true
                                text: I18n.tr("SWITCH TO WI-FI")
                                onAct: root.client.call("adbWifi", [])
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    implicitHeight: webcamBody.implicitHeight + Tokens.s4 * 2
                    radius: Tokens.radius
                    color: Tokens.paperLift
                    border.width: Tokens.border
                    border.color: root.webcam.running || root.webcam.starting ? Tokens.lineStrong : Tokens.lineSoft
                    Column {
                        id: webcamBody
                        anchors.fill: parent
                        anchors.margins: Tokens.s4
                        spacing: Tokens.s3
                        Row {
                            width: parent.width
                            spacing: Tokens.s3
                            Text {
                                text: "videocam"
                                color: Tokens.inkDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: Tokens.fValue
                            }
                            Column {
                                width: Math.max(0, parent.width - Tokens.s7)
                                Text {
                                    text: I18n.tr("Webcam")
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fRow
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: I18n.tr("Apps see it as Ryoku Phone")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                }
                            }
                        }
                        Text {
                            visible: String(root.webcam.error || "").length > 0
                            width: parent.width
                            text: String(root.webcam.error || "")
                            color: Tokens.alert
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                        Row {
                            spacing: Tokens.s3
                            Seg {
                                visible: root.webcamReady
                                options: ["back", "front"]
                                labels: ({ back: I18n.tr("Back"), front: I18n.tr("Front") })
                                current: String(root.webcam.facing || "back")
                                onChose: value => root.client.call("webcamFacing", [value])
                            }
                            Btn {
                                visible: root.webcamReady
                                text: root.webcam.running ? I18n.tr("STOP")
                                    : root.webcam.starting ? I18n.tr("STARTING...") : I18n.tr("START")
                                primary: !root.webcam.running
                                armed: root.webcam.running === true
                                    || (root.scrcpy.installed === true && root.webcam.starting !== true)
                                onAct: root.client.call(root.webcam.running ? "webcamStop" : "webcamStart", [])
                            }
                            Btn {
                                visible: !root.webcamReady
                                text: I18n.tr("FINISH SETUP")
                                primary: true
                                onAct: root.setupAndClose()
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    implicitHeight: micBody.implicitHeight + Tokens.s4 * 2
                    radius: Tokens.radius
                    color: Tokens.paperLift
                    border.width: Tokens.border
                    border.color: root.mic.running || root.mic.starting ? Tokens.lineStrong : Tokens.lineSoft
                    Column {
                        id: micBody
                        anchors.fill: parent
                        anchors.margins: Tokens.s4
                        spacing: Tokens.s3
                        Row {
                            width: parent.width
                            spacing: Tokens.s3
                            Text {
                                text: "mic"
                                color: Tokens.inkDim
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: Tokens.fValue
                            }
                            Column {
                                width: Math.max(0, parent.width - Tokens.s7)
                                Text {
                                    text: I18n.tr("Microphone")
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fRow
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: I18n.tr("Apps see it as Ryoku Phone mic")
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                }
                            }
                        }
                        Text {
                            visible: String(root.mic.error || "").length > 0
                            width: parent.width
                            text: String(root.mic.error || "")
                            color: Tokens.alert
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                        Btn {
                            text: root.mic.running ? I18n.tr("STOP")
                                : root.mic.starting ? I18n.tr("STARTING...") : I18n.tr("START")
                            primary: !root.mic.running
                            armed: root.mic.running === true
                                || (root.scrcpy.installed === true && root.mic.starting !== true)
                            onAct: root.client.call(root.mic.running ? "micStop" : "micStart", [])
                        }
                    }
                }

            }
                Row {
                    visible: root.scrcpy.installed !== true
                    width: parent.width
                    spacing: Tokens.s3
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, parent.width - setupAgain.width - parent.spacing)
                        text: I18n.tr("scrcpy is not installed, so phone video features cannot start.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        wrapMode: Text.WordWrap
                    }
                    Btn {
                        id: setupAgain
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("RUN SETUP AGAIN")
                        onAct: root.setupAndClose()
                    }
                }
        }
    }
}
