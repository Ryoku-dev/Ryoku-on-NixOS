pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    property var kit
    readonly property bool kitReady: Boolean(kit && kit.ready)
    property bool current: false
    property string railCurrent: "password"
    signal requestClose()

    property string selectedToolId: ""
    property string inputText: ""
    property string modifiedText: ""
    property string outputText: ""
    property string errorText: ""
    property string noticeText: ""
    property var activeOptions: ({})
    property var inputs: ({})
    property var modifiedInputs: ({})
    property real pageReveal: 1
    property real toolReveal: 1
    property real outputReveal: 1
    readonly property string diffSeparator: "\n===DIFF_SPLIT===\n"
    readonly property var selectedTool: registry.byId(selectedToolId)
    readonly property bool isGenerator: selectedTool?.type === "generator"
    readonly property bool isDiff: selectedToolId === "text_diff"
    readonly property bool needsSecureRandom: ["password", "uuid"].includes(selectedToolId)
    readonly property bool selectedAvailable: !needsSecureRandom || randomSource.ready
    readonly property bool randomPending: needsSecureRandom && !randomSource.ready && randomSource.error.length === 0
    opacity: 0.84 + pageReveal * 0.16
    transform: Translate { x: (1 - root.pageReveal) * 10 }

    function revealPage() {
        if (!current)
            return;
        if (Tokens.reduceMotion) {
            pageReveal = 1;
            return;
        }
        pageReveal = 0;
        pageRevealAnimation.restart();
    }

    function revealTool() {
        if (Tokens.reduceMotion) {
            toolReveal = 1;
            return;
        }
        toolReveal = 0;
        toolRevealAnimation.restart();
    }

    function revealOutput() {
        if (Tokens.reduceMotion || outputText.length === 0) {
            outputReveal = 1;
            return;
        }
        outputReveal = 0;
        outputRevealAnimation.restart();
    }

    function stored(key, fallback) {
        try {
            return kit ? kit.get(key, fallback) : fallback;
        } catch (error) {
            return fallback;
        }
    }

    function remember(key, value) {
        try {
            if (kit && (kit.ready === undefined || kit.ready))
                kit.set(key, value);
        } catch (error) {
        }
    }

    function loadTool(id) {
        const tool = registry.byId(id);
        if (!tool) {
            selectedToolId = "";
            activeOptions = ({});
            inputText = "";
            modifiedText = "";
            outputText = "";
            errorText = "";
            return;
        }

        selectedToolId = tool.id;
        activeOptions = Object.assign({}, tool.defaultOptions ?? {}, stored("devtools.options." + tool.id, {}));
        if (inputs[tool.id] === undefined) {
            const sample = tool.type === "generator" ? "" : String(tool.sampleInput ?? "");
            const parts = tool.id === "text_diff" ? sample.split(diffSeparator) : [sample];
            const nextInputs = Object.assign({}, inputs);
            const nextModified = Object.assign({}, modifiedInputs);
            nextInputs[tool.id] = parts[0] ?? "";
            nextModified[tool.id] = parts[1] ?? "";
            inputs = nextInputs;
            modifiedInputs = nextModified;
        }
        inputText = String(inputs[tool.id] ?? "");
        modifiedText = String(modifiedInputs[tool.id] ?? "");
        execute(false);
    }

    function setInput(value) {
        inputText = String(value ?? "");
        if (selectedTool) {
            const next = Object.assign({}, inputs);
            next[selectedTool.id] = inputText;
            inputs = next;
        }
    }

    function setModified(value) {
        modifiedText = String(value ?? "");
        if (selectedTool) {
            const next = Object.assign({}, modifiedInputs);
            next[selectedTool.id] = modifiedText;
            modifiedInputs = next;
        }
    }

    function setOption(key, value) {
        const next = Object.assign({}, activeOptions);
        next[key] = value;
        activeOptions = next;
        if (selectedTool)
            remember("devtools.options." + selectedTool.id, next);
        execute(false);
    }

    function execute(feedback) {
        const tool = selectedTool;
        if (!tool)
            return false;
        if (!selectedAvailable) {
            outputText = "";
            errorText = randomSource.error;
            return false;
        }
        const input = tool.type === "generator" ? "" : (isDiff ? inputText + diffSeparator + modifiedText : inputText);
        let options = Object.assign({}, activeOptions);
        if (needsSecureRandom)
            options = randomSource.options(options);
        try {
            const result = registry.run(tool.id, input, options);
            errorText = result.error ? String(result.error) : "";
            outputText = result.error ? "" : String(result.output ?? "");
            if (feedback && !result.error)
                showNotice(tool.type === "generator" ? I18n.tr("Generated") : I18n.tr("Completed"));
        } catch (error) {
            outputText = "";
            errorText = String(error);
        }
        if (needsSecureRandom)
            randomSource.replenishSoon();
        return errorText.length === 0;
    }

    function copyOutput() {
        if (outputText.length === 0)
            execute(false);
        if (outputText.length === 0)
            return false;
        Quickshell.clipboardText = outputText;
        showNotice(I18n.tr("Output copied"));
        return true;
    }

    function pasteInput() {
        if (isGenerator || !selectedTool)
            return false;
        setInput(String(Quickshell.clipboardText ?? ""));
        execute(false);
        showNotice(I18n.tr("Clipboard pasted"));
        return true;
    }

    function clearInput() {
        if (isGenerator || !selectedTool)
            return false;
        setInput("");
        if (isDiff)
            setModified("");
        execute(false);
        return true;
    }

    function chainOutput() {
        if (isGenerator || !selectedTool || outputText.length === 0)
            return false;
        setInput(outputText);
        execute(false);
        showNotice(I18n.tr("Output moved to input"));
        return true;
    }

    function showNotice(message) {
        noticeText = message;
        noticeTimer.restart();
    }

    function activate() {
        if (selectedTool && !isGenerator)
            inputPane.grabFocus();
        else
            root.forceActiveFocus();
    }

    function handleEscape() {
        if (inputPane.focused || modifiedPane.focused || outputPane.focused) {
            root.forceActiveFocus();
            return true;
        }
        return false;
    }

    onCurrentChanged: if (current) Qt.callLater(revealPage)
    onSelectedToolIdChanged: revealTool()
    onOutputTextChanged: revealOutput()
    onRailCurrentChanged: loadTool(railCurrent)
    onKitReadyChanged: if (kitReady) loadTool(railCurrent)
    Component.onCompleted: {
        loadTool(railCurrent);
        if (current)
            revealPage();
    }


    NumberAnimation {
        id: pageRevealAnimation
        target: root
        property: "pageReveal"
        from: 0
        to: 1
        duration: Tokens.durSmall
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: toolRevealAnimation
        target: root
        property: "toolReveal"
        from: 0
        to: 1
        duration: Tokens.durSmall
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: outputRevealAnimation
        target: root
        property: "outputReveal"
        from: 0
        to: 1
        duration: Tokens.snap
        easing.type: Easing.OutCubic
    }

    SecureRandom {
        id: randomSource
        onPoolReady: Qt.callLater(() => {
            if (root.needsSecureRandom)
                root.execute(false);
        })
        onErrorChanged: if (!ready && root.needsSecureRandom) root.errorText = error
    }

    DevToolsRegistry { id: registry }

    Timer {
        id: noticeTimer
        interval: 2200
        onTriggered: root.noticeText = ""
    }

    Shortcut { sequence: "Ctrl+Return"; onActivated: root.execute(true) }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: root.copyOutput() }
    Shortcut { sequence: "Ctrl+Shift+V"; onActivated: root.pasteInput() }
    Shortcut { sequence: "Ctrl+L"; onActivated: root.clearInput() }

    Item {
        id: workspace
        anchors.fill: parent
        opacity: 0.78 + root.toolReveal * 0.22
        transform: Translate { x: (1 - root.toolReveal) * 8 }

        Column {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.s1

            Text {
                width: parent.width
                text: root.selectedTool?.name ?? I18n.tr("No matching tools")
                color: Tokens.ink
                font.family: Tokens.display
                font.pixelSize: Tokens.fValue
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.selectedTool?.description ?? I18n.tr("Try a different search.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                elide: Text.ElideRight
            }
        }

        Item {
            id: optionArea
            anchors.top: header.bottom
            anchors.topMargin: Tokens.s3
            anchors.left: parent.left
            anchors.right: parent.right
            readonly property int optionCount: root.selectedTool?.options?.length ?? 0
            readonly property int columns: Math.max(1, Math.min(optionCount,
                width >= 620 ? 3 : (width >= 380 ? 2 : 1)))
            height: visible ? optionFlow.height : 0
            visible: optionCount > 0

            Flow {
                id: optionFlow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Tokens.s3
                height: childrenRect.height

                Repeater {
                    model: root.selectedTool?.options ?? []
                    delegate: ToolOption {
                        required property var modelData
                        required property int index
                        width: (optionFlow.width - Tokens.s3 * (optionArea.columns - 1)) / optionArea.columns
                        entranceIndex: index
                        option: modelData
                        value: root.activeOptions[modelData.id] !== undefined ? root.activeOptions[modelData.id] : modelData.default
                        onChanged: value => root.setOption(modelData.id, value)
                    }
                }
            }
        }

        Row {
            id: actions
            anchors.top: optionArea.visible ? optionArea.bottom : header.bottom
            anchors.topMargin: Tokens.s3
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Tokens.s2

            Btn {
                text: root.isGenerator ? I18n.tr("Generate") : I18n.tr("Run")
                primary: true
                armed: root.selectedTool !== null && root.selectedAvailable
                onAct: root.execute(true)
            }
            Btn {
                text: I18n.tr("Copy")
                armed: root.outputText.length > 0
                onAct: root.copyOutput()
            }
            Btn {
                text: I18n.tr("Use output as input")
                visible: !root.isGenerator
                armed: root.outputText.length > 0
                onAct: root.chainOutput()
            }
            Btn {
                text: I18n.tr("Paste")
                visible: !root.isGenerator
                onAct: root.pasteInput()
            }
            Btn {
                text: I18n.tr("Clear")
                visible: !root.isGenerator
                onAct: root.clearInput()
            }
        }

        Text {
            id: status
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: actions.bottom
            anchors.topMargin: Tokens.s2
            height: Tokens.fSmall + Tokens.s1
            text: root.noticeText.length > 0 ? root.noticeText
                : (root.errorText.length > 0 ? root.errorText
                : (root.randomPending ? I18n.tr("Preparing secure random source…") : ""))
            color: root.errorText.length > 0 ? Tokens.alert : Tokens.inkMuted
            Behavior on color {
                enabled: !Tokens.reduceMotion
                ColorAnimation { duration: Tokens.snap }
            }
            font.family: Tokens.ui
            font.pixelSize: Tokens.fTiny
            elide: Text.ElideRight
        }

        Item {
            id: editors
            anchors.top: status.bottom
            anchors.topMargin: Tokens.s2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            visible: root.selectedTool !== null

            Item {
                id: inputColumn
                visible: !root.isGenerator
                width: visible ? (parent.width - Tokens.s3) * 0.5 : 0
                height: parent.height

                TextPane {
                    id: inputPane
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: root.isDiff ? (parent.height - Tokens.s3) * 0.5 : parent.height
                    placeholder: I18n.tr("Input")
                    text: root.inputText
                    onEdited: value => root.setInput(value)
                }
                TextPane {
                    id: modifiedPane
                    visible: root.isDiff
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: inputPane.bottom
                    anchors.topMargin: Tokens.s3
                    anchors.bottom: parent.bottom
                    placeholder: I18n.tr("Modified text")
                    text: root.modifiedText
                    onEdited: value => root.setModified(value)
                }
            }

            TextPane {
                id: outputPane
                opacity: 0.72 + root.outputReveal * 0.28
                transform: Translate { y: (1 - root.outputReveal) * 4 }
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: inputColumn.visible ? inputColumn.right : parent.left
                anchors.leftMargin: inputColumn.visible ? Tokens.s3 : 0
                anchors.right: parent.right
                readOnly: true
                error: root.errorText.length > 0
                placeholder: root.errorText.length > 0 ? root.errorText
                    : (root.randomPending ? I18n.tr("Preparing secure random source…") : I18n.tr("Output"))
                text: root.outputText
            }
        }
    }
}
