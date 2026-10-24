pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Ryoku.Blobs
import Ryoku.Ui.Singletons
import shell.services

Rectangle {
    id: root

    required property real s
    property bool active: false
    property string mode: "ask"
    property string phase: "idle"
    property string working: ""
    property bool chatBusy: false
    property string chatActivity: ""
    property bool pendingHandoff: false
    property bool horizontalNavigation: false
    property bool typing: false
    property alias text: input.text
    property alias inputItem: input
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce
    readonly property bool workingActive: phase === "working" || (mode === "chat" && chatBusy)
    // Green for a readable link only; ordinary typing is never marked wrong.
    readonly property bool linkOk: mode === "tools"
        && /^https?:\/\/[^\s\/?#]+(?:[\/?#][^\s]*)?$/i.test(String(text).trim())

    signal submitted(string text)
    signal prefixRequested(string mode, string text)
    signal tabRequested()
    signal upRequested()
    signal downRequested()
    signal leftRequested()
    signal rightRequested()
    signal newChatRequested()
    signal escapeRequested()
    signal historyRequested()
    signal modelRequested()

    implicitHeight: 72 * s
    radius: Tokens.radius * s
    color: Tokens.paperLift
    border.width: workingActive ? 2 * s : input.activeFocus ? 1.5 * s : Tokens.border
    // Tertiary follows the wallpaper.
    border.color: workingActive ? Tokens.bone
        : root.linkOk ? Scheme.tertiary
        : input.activeFocus ? Qt.alpha(Tokens.bone, 0.72) : Tokens.line
    scale: input.activeFocus && motionAllowed ? 1.006 : 1

    function focusField() {
        Qt.callLater(() => input.forceActiveFocus());
    }

    onActiveChanged: {
        if (active) {
            focusField();
        } else {
            typing = false;
            typingTimer.stop();
        }
    }

    Timer {
        id: typingTimer
        interval: 600
        onTriggered: root.typing = false
    }
    RectangularShadow {
        anchors.fill: parent
        z: -1
        radius: root.radius
        blur: 8 * root.s
        spread: 1.5 * root.s
        color: Qt.alpha(Tokens.bone, 0.26)
        opacity: input.activeFocus ? 1 : 0
        visible: opacity > 0.001
        Behavior on opacity {
            enabled: root.motionAllowed
            NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease }
        }
    }


    BorderBeam {
        anchors.fill: parent
        z: 0
        mode: "line"
        radius: root.radius
        color: Tokens.bone
        strokeWidth: 2.25 * root.s
        blur: 2.5 * root.s
        strength: 1
        duration: 2.6
        active: root.workingActive && root.motionAllowed
    }

    AskOrb {
        id: orb
        anchors.left: parent.left
        anchors.leftMargin: Tokens.s4 * root.s
        anchors.verticalCenter: parent.verticalCenter
        z: 1
        s: root.s
        active: root.active
        phase: root.phase
        working: root.working
        mode: root.mode
        typing: root.typing
        chatBusy: root.chatBusy
        chatActivity: root.chatActivity
        opacity: root.active ? 1 : 0
        scale: root.active ? 1 : 0.72
        Behavior on opacity {
            enabled: root.motionAllowed
            NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease }
        }
        Behavior on scale {
            enabled: root.motionAllowed
            NumberAnimation { duration: Motion.spatial; easing.type: Easing.OutBack }
        }
    }

    TextInput {
        id: input
        z: 1
        anchors.left: orb.right
        anchors.right: keycap.left
        anchors.leftMargin: Tokens.s4 * root.s
        anchors.rightMargin: Tokens.s4 * root.s
        anchors.verticalCenter: parent.verticalCenter
        color: Tokens.ink
        selectionColor: Tokens.bone
        selectedTextColor: Tokens.inkOnBone
        font.family: Tokens.ui
        font.pixelSize: Tokens.fValue * root.s
        selectByMouse: true
        clip: true
        verticalAlignment: TextInput.AlignVCenter

        property bool prefixGuard: false

        onTextEdited: {
            root.typing = true;
            typingTimer.restart();
            if (prefixGuard || text.length === 0)
                return;
            const prefix = text.charAt(0);
            let next = "";
            if (prefix === "?") next = "web";
            else if (prefix === "/") next = "tools";
            else if (prefix === "\\") next = "ask";
            if (next.length === 0)
                return;
            prefixGuard = true;
            const remainder = text.slice(1);
            root.prefixRequested(next, remainder);
            Qt.callLater(() => input.cursorPosition = input.text.length);
            prefixGuard = false;
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab) {
                root.tabRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)
                    && root.mode === "chat") {
                root.newChatRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_Up) {
                root.upRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_Down) {
                root.downRequested();
                event.accepted = true;
            } else if (root.horizontalNavigation && event.key === Qt.Key_Left) {
                root.leftRequested();
                event.accepted = true;
            } else if (root.horizontalNavigation && event.key === Qt.Key_Right) {
                root.rightRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.escapeRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_H
                    && (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                        === (Qt.ControlModifier | Qt.ShiftModifier)) {
                root.historyRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_M
                    && (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
                        === (Qt.ControlModifier | Qt.ShiftModifier)) {
                root.modelRequested();
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submitted(text);
                event.accepted = true;
            }
        }
    }

    Text {
        z: 1
        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter
        visible: input.text.length === 0
        text: root.mode === "chat" && root.pendingHandoff ? I18n.tr("Continue from the ask…")
            : root.mode === "chat" ? I18n.tr("Message Rashin…")
            : root.mode === "web" ? I18n.tr("Search the web…")
            : root.mode === "tools" ? I18n.tr("Pick a tool…")
            : I18n.tr("Ask anything…")
        color: Tokens.inkFaint
        font.family: Tokens.ui
        font.pixelSize: Tokens.fValue * root.s
    }

    Rectangle {
        z: 1
        id: keycap
        anchors.right: parent.right
        anchors.rightMargin: Tokens.s4 * root.s
        anchors.verticalCenter: parent.verticalCenter
        width: enterLabel.implicitWidth + Tokens.s3 * root.s
        height: Tokens.ctlH * root.s
        radius: Tokens.radius * root.s
        color: Tokens.tint5
        border.width: Tokens.border
        border.color: Tokens.lineSoft
        Text {
            id: enterLabel
            anchors.centerIn: parent
            text: I18n.tr("Enter")
            color: Tokens.inkMuted
            font.family: Tokens.mono
            font.pixelSize: Tokens.fTiny * root.s
        }
    }

    Behavior on border.color {
        enabled: root.motionAllowed
        ColorAnimation { duration: Tokens.snap }
    }
    Behavior on border.width {
        enabled: root.motionAllowed
        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }
    Behavior on scale {
        enabled: root.motionAllowed
        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }
}
