pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui.Singletons

Scope {
    id: root

    property string question: ""
    property string phase: "idle"
    property string working: ""
    property string answerText: ""
    property var answerImages: []
    property var answerActions: []
    property string answerId: ""
    property string answerVia: ""
    property bool needsAgent: false
    property string needsAgentReason: ""
    property string errorText: ""
    property string askedQuestion: ""
    property var recent: []
    property bool recentOpen: false
    property bool fromHistory: false

    readonly property bool busy: phase === "working"
    readonly property bool answerCurrent: phase === "done"
        && (fromHistory || question.trim() === askedQuestion)

    signal answered()

    function reset() {
        askProc.running = false;
        recentProc.running = false;
        phase = "idle";
        working = "";
        answerText = "";
        answerImages = [];
        answerActions = [];
        answerId = "";
        answerVia = "";
        needsAgent = false;
        needsAgentReason = "";
        errorText = "";
        askedQuestion = "";
        recent = [];
        recentOpen = false;
        fromHistory = false;
    }

    function ask(value) {
        if (busy)
            return;
        const next = String(value === undefined ? question : value).trim();
        if (next === "resume" || next === "recent") {
            requestRecent();
            return;
        }
        if (next.length === 0)
            return;
        answerText = "";
        answerImages = [];
        answerActions = [];
        answerId = "";
        answerVia = "";
        needsAgent = false;
        needsAgentReason = "";
        errorText = "";
        fromHistory = false;
        recentOpen = false;
        askedQuestion = next;
        working = I18n.tr("waking the needle");
        phase = "working";
        // sh-wrapped like the Hub's Rashin page: a box without ryoku-rashin
        // still exits (127) instead of never starting, so the ask cannot hang.
        askProc.command = ["sh", "-c", "exec ryoku-rashin ask \"$1\"", "sh", next];
        askProc.running = true;
    }

    function requestRecent() {
        if (busy)
            return;
        recentOpen = true;
        phase = "idle";
        recent = [];
        recentProc.command = ["ryoku-rashin", "ask", "--recent"];
        recentProc.running = true;
    }

    function loadRecent(entry) {
        answerText = String(entry && entry.a || "");
        answerImages = entry && entry.images || [];
        answerActions = entry && entry.actions || [];
        answerId = String(entry && entry.id || "");
        answerVia = String(entry && entry.via || "");
        needsAgent = entry && entry.needsAgent === true;
        needsAgentReason = String(entry && entry.needsAgentReason || "");
        askedQuestion = String(entry && entry.q || "");
        fromHistory = true;
        recentOpen = false;
        errorText = "";
        phase = "done";
        answered();
    }

    function cancel() {
        phase = "cancelled";
        working = "";
        askProc.running = false;
        Quickshell.execDetached(["ryoku-rashin", "ask", "--cancel"]);
    }

    Process {
        id: recentProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(this.text);
                    root.recent = Array.isArray(parsed) ? parsed : [];
                } catch (error) {
                    root.recent = [];
                }
            }
        }
    }

    Process {
        id: askProc
        stdout: SplitParser {
            onRead: line => {
                const marker = String(line);
                if (marker.indexOf("@working ") === 0) {
                    root.working = marker.slice(9);
                } else if (marker.indexOf("@answer ") === 0) {
                    try {
                        const answer = JSON.parse(marker.slice(8));
                        root.answerText = String(answer.text || "");
                        root.answerImages = answer.images || [];
                        root.answerActions = answer.actions || [];
                        root.answerId = String(answer.id || "");
                        root.answerVia = String(answer.via || "");
                        root.needsAgent = answer.needsAgent === true;
                        root.needsAgentReason = String(answer.needsAgentReason || "");
                        root.fromHistory = false;
                        root.phase = "done";
                        root.answered();
                    } catch (error) {
                        root.errorText = I18n.tr("Unreadable answer");
                        root.phase = "failed";
                    }
                } else if (marker.indexOf("@error ") === 0) {
                    root.errorText = marker.slice(7);
                    root.phase = "failed";
                }
            }
        }
        onExited: code => {
            if (root.phase === "working") {
                root.errorText = code === 0 ? I18n.tr("No answer")
                    : code === 127 ? I18n.tr("Rashin is off · switch it on in Ryoku Hub")
                    : I18n.tr("Ask failed");
                root.phase = "failed";
            }
        }
    }
}
