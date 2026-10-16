pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons

Flickable {
    id: viewport

    required property var engine
    required property var store
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: words.implicitHeight
    readonly property real lineHeight: Math.round(store.fontSize * 1.58)
    implicitHeight: lineHeight * Math.max(2, store.visibleLines)
        + Tokens.s3 * Math.max(0, Math.max(2, store.visibleLines) - 1)

    function wordInput(index) {
        const parts = String(engine.inputText || "").split(" ");
        return index < parts.length ? parts[index] : "";
    }

    function charColor(wordIndex, charIndex, target, typed) {
        if (charIndex >= typed.length)
            return Tokens.inkMuted;
        if (store.blindMode)
            return Tokens.ink;
        return Array.from(typed)[charIndex] === Array.from(target)[charIndex]
            ? Tokens.ink : Tokens.alert;
    }

    function revealCurrent() {
        const item = wordRepeater.itemAt(engine.currentWordIndex);
        if (!item)
            return;
        const top = item.y;
        const bottom = top + item.height;
        if (top < contentY + lineHeight)
            contentY = Math.max(0, top - lineHeight);
        else if (bottom > contentY + height - lineHeight)
            contentY = Math.min(Math.max(0, contentHeight - height), bottom - height + lineHeight);
    }

    Connections {
        target: viewport.engine
        function onCurrentWordIndexChanged() { Qt.callLater(viewport.revealCurrent); }
        function onResetRequested() { viewport.contentY = 0; }
    }

    Flow {
        id: words
        width: viewport.width
        spacing: Tokens.s3
        flow: Flow.LeftToRight

        Repeater {
            id: wordRepeater
            model: viewport.engine.targetWords
            delegate: Row {
                id: word
                required property string modelData
                required property int index
                readonly property string typed: viewport.wordInput(index)
                readonly property var targetChars: Array.from(modelData)
                readonly property var typedChars: Array.from(typed)
                readonly property bool current: index === viewport.engine.currentWordIndex
                height: viewport.lineHeight
                spacing: 0
                opacity: viewport.store.highlightCurrentWord && !current ? 0.38 : 1
                Behavior on opacity { NumberAnimation { duration: Tokens.snap } }

                Repeater {
                    model: word.targetChars
                    delegate: Text {
                        required property string modelData
                        required property int index
                        text: modelData
                        color: viewport.charColor(word.index, index, word.modelData, word.typed)
                        font.family: viewport.engine.languagePack && viewport.engine.languagePack.preferredFont
                            ? viewport.engine.languagePack.preferredFont : Tokens.mono
                        font.pixelSize: viewport.store.fontSize
                        font.weight: Font.Medium
                        height: viewport.lineHeight
                        verticalAlignment: Text.AlignVCenter

                        Rectangle {
                            visible: word.current && viewport.store.caretStyle !== "off"
                                && parent.index === Math.min(word.targetChars.length - 1, word.typedChars.length)
                            x: word.typedChars.length >= word.targetChars.length ? parent.width : 0
                            y: viewport.store.caretStyle === "underline" ? parent.height - 5 : 4
                            width: viewport.store.caretStyle === "block" ? Math.max(2, parent.width)
                                : (viewport.store.caretStyle === "underline" ? Math.max(2, parent.width) : 2)
                            height: viewport.store.caretStyle === "block" ? parent.height - 8
                                : (viewport.store.caretStyle === "underline" ? 2 : parent.height - 8)
                            color: Tokens.ink
                            opacity: viewport.store.caretStyle === "block" ? 0.28 : 1
                            Behavior on x {
                                enabled: viewport.store.smoothCaret
                                NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                            }
                        }
                    }
                }

                Text {
                    visible: word.typedChars.length > word.targetChars.length
                    text: word.typedChars.slice(word.targetChars.length).join("")
                    color: viewport.store.blindMode ? Tokens.ink : Tokens.alert
                    font.family: Tokens.mono
                    font.pixelSize: viewport.store.fontSize
                    font.weight: Font.Medium
                    height: viewport.lineHeight
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
