pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var client
    signal requestClose()
    property bool helpOpen: false

    readonly property bool installedAndOn: client.state.installed === true && client.state.enabled === true
    readonly property bool found: client.devices.length > 0
    readonly property bool paired: client.pairedDevices.length > 0
    readonly property int currentStep: !installedAndOn ? 1 : !found ? 2 : 3
    readonly property var installState: client.state.install || ({})
    readonly property var kdeconnect: client.state.kdeconnect || ({})
    readonly property string outgoing: String((client.state.pairing || {}).outgoing || "")

    function activate() {
        if (currentStep === 1)
            installButton.forceActiveFocus();
        else if (currentStep === 2)
            helpButton.forceActiveFocus();
        else
            root.forceActiveFocus();
    }

    function handleEscape() {
        if (root.helpOpen) {
            root.helpOpen = false;
            return true;
        }
        return false;
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentHeight: Math.max(height, content.implicitHeight + Tokens.s6 * 2)
        ScrollBar.vertical: ScrollRail {
            policy: ScrollBar.AsNeeded
            visible: scroll.contentHeight > scroll.height + 1
        }
        WheelScroll { }

        Column {
            id: content
            anchors.top: parent.top
            anchors.topMargin: Tokens.s6
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(720, scroll.width - Tokens.s6 * 2)
            spacing: Tokens.s5

            Column {
                width: parent.width
                spacing: Tokens.s2
                Text {
                    text: I18n.tr("PHONE")
                    color: Tokens.inkMuted
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                    font.letterSpacing: Tokens.trackMark
                }
                Text {
                    width: parent.width
                    text: root.client.state.installed === true && root.client.state.enabled !== true
                        ? I18n.tr("Turn phone support on") : I18n.tr("Connect your phone")
                    color: Tokens.ink
                    font.family: Tokens.display
                    font.pixelSize: Tokens.fTitle
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    text: I18n.tr("Follow these three steps once, then your phone stays close at hand.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }
            }

            Column {
                width: parent.width
                spacing: Tokens.s2

                PhoneSetupStep {
                    width: parent.width
                    step: 1
                    title: root.client.state.installed === true && root.client.state.enabled !== true
                        ? I18n.tr("Turn phone support on") : I18n.tr("Install phone support")
                    description: root.client.state.installed === true
                        ? I18n.tr("Starts KDE Connect so this computer can find your phone.")
                        : I18n.tr("Adds KDE Connect, scrcpy and Android tools. You'll be asked for your password.")
                    done: root.installedAndOn
                    current: root.currentStep === 1

                    Row {
                        spacing: Tokens.s2
                        Btn {
                            id: installButton
                            visible: root.installState.busy !== true
                                && String(root.installState.error || "").length === 0
                            primary: true
                            text: root.client.state.installed === true ? I18n.tr("TURN ON") : I18n.tr("INSTALL")
                            onAct: {
                                root.client.call("install", []);
                                root.requestClose();
                            }
                        }
                        Text {
                            visible: root.installState.busy === true
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Installing... you can close this")
                            color: Tokens.inkDim
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                        }
                    }
                    Column {
                        visible: String(root.installState.error || "").length > 0
                        width: parent.width
                        spacing: Tokens.s2
                        Text {
                            width: parent.width
                            text: String(root.installState.error || "")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                        Btn {
                            text: I18n.tr("TRY AGAIN")
                            onAct: {
                                root.client.call("install", []);
                                root.requestClose();
                            }
                        }
                    }
                }

                PhoneSetupStep {
                    width: parent.width
                    step: 2
                    title: I18n.tr("Get KDE Connect on your phone")
                    description: I18n.tr("Install KDE Connect from Google Play or F-Droid, open it, and keep the phone on the same Wi-Fi as this computer.")
                    done: root.found
                    current: root.currentStep === 2

                    Row {
                        spacing: Tokens.s2
                        Text {
                            id: spinner
                            visible: root.currentStep === 2 && !root.found
                            text: "progress_activity"
                            color: Tokens.inkDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: Tokens.fBody
                            RotationAnimator on rotation {
                                running: spinner.visible && !Tokens.reduceMotion
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: Tokens.durNormal * 2
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Looking for your phone...")
                            color: Tokens.inkDim
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                        }
                    }

                    Text {
                        visible: root.client.state.networkIsolation === true
                        width: parent.width
                        text: I18n.tr("Ryoku's network isolation is on. Turn it off in Controls, then refresh.")
                        color: Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        wrapMode: Text.WordWrap
                    }

                    Btn {
                        id: helpButton
                        text: root.helpOpen ? I18n.tr("HIDE HELP") : I18n.tr("NOT SHOWING UP?")
                        onAct: root.helpOpen = !root.helpOpen
                    }

                    Rectangle {
                        visible: height > 0
                        width: parent.width
                        height: root.helpOpen ? help.implicitHeight + Tokens.s4 * 2 : 0
                        opacity: root.helpOpen ? 1 : 0
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
                            id: help
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Tokens.s4
                            spacing: Tokens.s2
                            Text {
                                width: parent.width
                                text: "1. " + I18n.tr("Keep both devices on the same Wi-Fi.")
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                width: parent.width
                                text: "2. " + I18n.tr("Open KDE Connect on your phone and leave it open.")
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                visible: root.kdeconnect.running === false
                                width: parent.width
                                text: I18n.tr("KDE Connect is not running on this computer. Try turning phone support on again.")
                                color: Tokens.ink
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                wrapMode: Text.WordWrap
                            }
                            Btn {
                                id: refreshButton
                                text: I18n.tr("REFRESH")
                                onAct: root.client.call("refresh", [])
                            }
                        }
                    }
                }

                PhoneSetupStep {
                    width: parent.width
                    step: 3
                    last: true
                    title: I18n.tr("Pair")
                    description: I18n.tr("Choose your phone here, then accept the same request on your phone.")
                    done: root.paired
                    current: root.currentStep === 3

                    Column {
                        width: parent.width
                        spacing: Tokens.s2
                        Repeater {
                            model: root.client.devices.filter(device => device && device.paired !== true)
                            delegate: Rectangle {
                                id: deviceRow
                                required property var modelData
                                width: parent.width
                                height: Tokens.rowH + Tokens.s2
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
                                        text: deviceRow.modelData.type === "tablet" ? "tablet" : "smartphone"
                                        color: Tokens.inkDim
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: Tokens.fBody
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(0, parent.width - pairButton.width - Tokens.s7)
                                        text: String(deviceRow.modelData.name || I18n.tr("Phone"))
                                        color: Tokens.ink
                                        font.family: Tokens.ui
                                        font.pixelSize: Tokens.fSmall
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    Btn {
                                        id: pairButton
                                        anchors.verticalCenter: parent.verticalCenter
                                        compact: true
                                        primary: root.outgoing !== String(deviceRow.modelData.id || "")
                                        armed: root.outgoing !== String(deviceRow.modelData.id || "")
                                        text: root.outgoing === String(deviceRow.modelData.id || "")
                                            ? I18n.tr("REQUEST SENT") : I18n.tr("PAIR")
                                        onAct: root.client.call("pair", [String(deviceRow.modelData.id || "")])
                                    }
                                }
                            }
                        }
                        Text {
                            visible: root.outgoing.length > 0
                            width: parent.width
                            text: I18n.tr("Accept the request on your phone")
                            color: Tokens.inkDim
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
