pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import shell.services as Svc
import "../../../services" as Services
import "Singletons"
import Ryoku.Ui.Singletons

Item {
    id: root

    property real s: 1
    property string question: ""
    property alias phase: askSession.phase
    property alias resumeMode: askSession.recentOpen
    property alias recent: askSession.recent
    property alias working: askSession.working
    property alias answerText: askSession.answerText
    property alias answerImages: askSession.answerImages
    property alias answerActions: askSession.answerActions
    property alias answerId: askSession.answerId
    property alias needsAgent: askSession.needsAgent
    property alias needsAgentReason: askSession.needsAgentReason
    property alias errorText: askSession.errorText
    property alias fromHistory: askSession.fromHistory
    property alias askedQuestion: askSession.askedQuestion
    property int selectedChip: 0
    property int selectedRecent: 0
    property string flash: ""
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce

    readonly property bool busy: askSession.busy
    readonly property bool answerCurrent: askSession.answerCurrent
    readonly property var workChips: [
        { kind: "chat", value: "", label: I18n.tr("CONTINUE IN CHAT") },
        { kind: "cancel", value: "", label: I18n.tr("CANCEL") }
    ]
    readonly property var chips: {
        if (busy)
            return workChips;
        if (phase !== "done")
            return [];
        const result = [];
        if (needsAgent)
            result.push({ kind: "chat", value: "", label: I18n.tr("OPEN CHAT") });
        result.push({ kind: "copy", value: answerText, label: I18n.tr("COPY") });
        for (let i = 0; i < answerActions.length; i++)
            result.push(answerActions[i]);
        if (!needsAgent)
            result.push({ kind: "chat", value: "", label: I18n.tr("OPEN CHAT") });
        return result;
    }

    signal finished()

    implicitHeight: col.implicitHeight

    Services.AskSession {
        id: askSession
        question: root.question
        onAnswered: root.selectedChip = 0
    }

    function reset() {
        askSession.reset();
        selectedChip = 0;
        selectedRecent = 0;
        flash = "";
    }

    function run() {
        selectedChip = 0;
        askSession.ask(root.question);
    }

    function openResume() {
        selectedRecent = 0;
        askSession.requestRecent();
    }

    function loadRecent(rec) {
        askSession.loadRecent(rec);
        selectedChip = 0;
    }

    function move(d) {
        if (resumeMode) {
            if (recent.length === 0)
                return;
            selectedRecent = Math.max(0, Math.min(recent.length - 1, selectedRecent + d));
            return;
        }
        if (chips.length > 0)
            selectedChip = Math.max(0, Math.min(chips.length - 1, selectedChip + d));
    }

    function activate() {
        if (resumeMode) {
            if (recent[selectedRecent])
                loadRecent(recent[selectedRecent]);
            return;
        }
        const chip = chips[selectedChip];
        if (chip)
            root.fire(chip);
    }

    function cancel() {
        askSession.cancel();
    }

    function fire(chip) {
        switch (chip.kind) {
        case "copy":
        case "cmd":
        case "color":
            Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "_", String(chip.value)]);
            root.flash = chip.kind + "\u0000" + chip.value;
            flashTimer.restart();
            return;
        case "cancel":
            root.cancel();
            root.finished();
            return;
        case "file":
<<<<<<< port (main)
            Spawn.runApp(["kitty", "-e", "nvim", String(chip.value)]);
            break;
        case "dir":
        case "url":
            Spawn.runApp(["xdg-open", String(chip.value)]);
=======
            Spawn.runApp(["kitty", "-e", "nvim", String(chip.value)], { label: "kitty" });
            break;
        case "dir":
        case "url":
            Spawn.runApp(["xdg-open", String(chip.value)], { label: chip.kind });
>>>>>>> upstream Ryoku 1.0.4 (ad2d365)
            break;
        case "chat": {
            const runAgent = busy || needsAgent;
            Svc.Needle.handoff(
                runAgent ? "" : answerId,
                askedQuestion,
                runAgent ? "" : answerText,
                runAgent
            );
            Svc.ShellState.requestSurfaceActive("ask#chat", undefined);
            break;
        }
        }
        root.finished();
    }

    function chipCaption(chip) {
        if (root.flash === chip.kind + "\u0000" + chip.value)
            return I18n.tr("COPIED");
        switch (chip.kind) {
        case "file": return "nvim " + chip.label;
        case "dir": return I18n.tr("open %1").arg(chip.label);
        case "url": return chip.label;
        case "cmd": return "$ " + chip.label;
        case "color": return chip.label;
        default: return chip.label;
        }
    }

    Timer {
        id: flashTimer
        interval: 1400
        onTriggered: root.flash = ""
    }

    Column {
        id: col
        width: parent.width
        spacing: 8 * root.s

        Text {
            width: parent.width
            text: root.resumeMode ? I18n.tr("RASHIN \u00b7 RECENT ASKS") : I18n.tr("RASHIN")
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
            font.letterSpacing: 1
        }

        // idle hint (not in resume mode)
        Text {
            width: parent.width
            visible: root.phase === "idle" && !root.resumeMode
            text: root.question.trim().length === 0
                ? I18n.tr("Ask the needle anything. ENTER sends; \\resume recalls recent asks.")
                : I18n.tr("ENTER to ask: %1").arg(root.question.trim())
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // resume list
        Column {
            width: parent.width
            visible: root.resumeMode
            spacing: 3 * root.s

            Text {
                visible: root.recent.length === 0
                text: I18n.tr("no recent asks yet")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: Metrics.fontSubtitle * root.s
            }

            Repeater {
                model: root.resumeMode ? root.recent : []
                delegate: Rectangle {
                    id: recRow
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: recCol.implicitHeight + 10 * root.s
                    radius: Theme.radius
                    color: index === root.selectedRecent ? Theme.tileBg : "transparent"

                    Column {
                        id: recCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 10 * root.s
                        anchors.rightMargin: 10 * root.s
                        spacing: 1 * root.s

                        Text {
                            width: parent.width
                            text: String(recRow.modelData.q || "")
                            color: recRow.index === root.selectedRecent ? Theme.bright : Theme.subtle
                            font.family: Theme.font
                            font.pixelSize: Metrics.fontSubtitle * root.s
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: String(recRow.modelData.a || "").replace(/\n/g, " ")
                            color: Theme.faint
                            font.family: Theme.mono
                            font.pixelSize: Metrics.fontEyebrow * root.s
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.loadRecent(recRow.modelData) }
                }
            }
        }

        // working strip: pulsing dot + live activity
        Row {
            visible: root.busy
            spacing: 8 * root.s

            Rectangle {
                width: 8 * root.s
                height: 8 * root.s
                radius: width / 2
                color: Theme.flameGlow
                anchors.verticalCenter: parent.verticalCenter

                SequentialAnimation on opacity {
                    running: root.busy
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.25; duration: 550; easing.type: Easing.InOutQuad }
                    NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutQuad }
                }
            }

            Text {
                text: root.working
                color: Theme.subtle
                font.family: Theme.mono
                font.pixelSize: Metrics.fontSubtitle * root.s
                font.letterSpacing: 1
                elide: Text.ElideRight
            }
        }

        // answer: selectable
        TextEdit {
            width: parent.width
            visible: root.phase === "done"
            text: root.answerText
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: TextEdit.Wrap
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.vermDimDeep
            selectedTextColor: Theme.bright
        }

        Text {
            visible: root.phase === "done" && root.fromHistory
            text: I18n.tr("from history")
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
        }

        // image results preview inline; click opens
        Row {
            visible: root.phase === "done" && root.answerImages.length > 0
            spacing: 8 * root.s

            Repeater {
                model: root.answerImages
                delegate: Image {
                    id: thumb
                    required property string modelData
                    source: "file://" + modelData
                    width: 96 * root.s
                    height: 96 * root.s
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true

                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
<<<<<<< port (main)
                            Spawn.runApp(["xdg-open", thumb.modelData]);
=======
                            Spawn.runApp(["xdg-open", thumb.modelData], { label: "image" });
>>>>>>> upstream Ryoku 1.0.4 (ad2d365)
                            root.finished();
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.phase === "failed"
            text: root.errorText
            color: Theme.verm
            font.family: Theme.mono
            font.pixelSize: Metrics.fontSubtitle * root.s
            wrapMode: Text.WordWrap
            maximumLineCount: 3
        }

        // action chips (working actions or answer chips)
        Flow {
            width: parent.width
            visible: root.chips.length > 0 && !root.resumeMode
            spacing: 6 * root.s

            Repeater {
                model: root.chips
                delegate: Rectangle {
                    id: chipBox
                    required property var modelData
                    required property int index

                    readonly property bool current: index === root.selectedChip
                    readonly property bool danger: modelData.kind === "cancel"
                    width: chipRow.implicitWidth + 18 * root.s
                    height: chipRow.implicitHeight + 10 * root.s
                    radius: Theme.radius
                    scale: chipTap.pressed && root.motionAllowed ? 0.94
                        : chipHover.hovered && root.motionAllowed ? 1.025 : 1
                    color: current || chipHover.hovered ? (danger ? Theme.vermDeep : Theme.verm) : "transparent"
                    border.color: current || chipHover.hovered ? (danger ? Theme.vermDeep : Theme.verm) : Theme.border
                    border.width: 1
                    Behavior on scale {
                        enabled: root.motionAllowed
                        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                    }

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6 * root.s

                        Rectangle {
                            visible: chipBox.modelData.kind === "color"
                            width: 10 * root.s
                            height: 10 * root.s
                            radius: Theme.radius
                            color: String(chipBox.modelData.value)
                            border.color: Theme.hair
                            border.width: 1
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: root.chipCaption(chipBox.modelData)
                            color: chipBox.current || chipHover.hovered ? Theme.cardTop : Theme.subtle
                            font.family: Theme.mono
                            font.pixelSize: Metrics.fontEyebrow * root.s
                            font.letterSpacing: 1
                        }
                    }

                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: chipTap; onTapped: root.fire(chipBox.modelData) }
                }
            }
        }

        // key hints
        Text {
            visible: root.chips.length > 0 || root.resumeMode
            text: root.resumeMode
                ? I18n.tr("\u2191\u2193 pick \u00b7 ENTER recall \u00b7 ESC back")
                : (root.busy
                    ? I18n.tr("\u2191\u2193 pick \u00b7 ENTER fires \u00b7 ESC cancels")
                    : I18n.tr("\u2191\u2193 walk chips \u00b7 ENTER fires \u00b7 type to re-ask \u00b7 ESC dismisses"))
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: Metrics.fontEyebrow * root.s
        }
    }
}
