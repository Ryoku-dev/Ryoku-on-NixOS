import QtQuick

// A reading that counts to its new value (volume 40 -> 62 runs through the
// numbers) instead of snapping. Whole numbers roll; anything else (a network
// name) fades through. Set `figure`, not `text`.
Text {
    id: root

    property string figure: ""
    property bool live: true
    readonly property int fadeMs: 140
    readonly property bool whole: /^-?\d+$/.test(figure)
    property real n: 0
    property string shown: figure

    text: whole && roll.running ? String(Math.round(n)) : shown

    onFigureChanged: {
        const was = shown;
        const digits = /^-?\d+$/;
        if (live && digits.test(figure) && digits.test(was) && was !== figure) {
            roll.stop();
            roll.from = Number(was);
            roll.to = Number(figure);
            roll.duration = Math.min(320, 120 + 6 * Math.abs(Number(figure) - Number(was)));
            shown = figure;
            roll.start();
        } else if (live && was !== figure && was !== "") {
            fade.restart();
        } else {
            shown = figure;
        }
    }

    NumberAnimation { id: roll; target: root; property: "n"; easing.type: Easing.OutCubic }

    SequentialAnimation {
        id: fade
        NumberAnimation { target: root; property: "opacity"; to: 0.2; duration: root.fadeMs / 2; easing.type: Easing.InQuad }
        ScriptAction { script: root.shown = root.figure }
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: root.fadeMs / 2; easing.type: Easing.OutQuad }
    }
}
