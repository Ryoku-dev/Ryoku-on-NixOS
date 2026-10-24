pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Blobs
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property real s
    property bool active: false
    property string phase: "idle"
    property string working: ""
    property string mode: "ask"
    property bool typing: false
    property bool chatBusy: false
    property string chatActivity: ""
    property string preset: "inline"
    property color ink: Tokens.ink
    property real orbSize: 28 * s
    property string transientState: ""
    readonly property bool motionAllowed: active && !Tokens.reduceMotion && !Motion.reduce
    readonly property string orbState: {
        if (mode === "tools" || mode === "web")
            return "breathing";
        if (mode === "chat") {
            if (!chatBusy)
                return typing ? "listening" : "breathing";
            const activity = chatActivity.toLowerCase();
            return activity.indexOf("writ") >= 0 || activity.indexOf("compos") >= 0
                ? "composing" : "working";
        }
        if (transientState.length > 0)
            return transientState;
        if (phase === "working") {
            const label = working.toLowerCase();
            if (label.indexOf("waking the needle") >= 0)
                return "connecting";
            if (label.indexOf("search") >= 0 || label.indexOf("read") >= 0
                    || label.indexOf("look") >= 0 || label.indexOf("find") >= 0
                    || label.indexOf("fetch") >= 0 || label.indexOf("browse") >= 0)
                return "searching";
            if (label.indexOf("thinking") >= 0)
                return "weaving";
            if (label.indexOf("writing") >= 0)
                return "composing";
            return "working";
        }
        return typing ? "listening" : "breathing";
    }

    implicitWidth: orbSize
    implicitHeight: orbSize

    function playTerminalState(next) {
        transientState = next;
        terminalTimer.restart();
    }

    onPhaseChanged: {
        if (phase === "done")
            playTerminalState("solving");
        else if (phase === "failed" || phase === "cancelled")
            playTerminalState("shaping");
        else if (phase === "working" || phase === "idle")
            transientState = "";
    }

    onActiveChanged: {
        if (!active) {
            transientState = "";
            terminalTimer.stop();
        } else if (phase === "done") {
            playTerminalState("solving");
        } else if (phase === "failed" || phase === "cancelled") {
            playTerminalState("shaping");
        }
    }

    Timer {
        id: terminalTimer
        interval: 1600
        onTriggered: root.transientState = ""
    }

    ThinkingOrb {
        anchors.fill: parent
        state: root.orbState
        preset: root.preset
        ink: root.ink
        animated: root.motionAllowed
    }
}
