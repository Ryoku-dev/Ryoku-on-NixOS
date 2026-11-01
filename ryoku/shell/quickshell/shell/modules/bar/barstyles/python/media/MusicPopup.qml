import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Effects
import "../"
import "../reusables"

MusicEqualizerState {
    id: popupRoot
    visible: false
    focus: true

<<<<<<< port (unstable-dev)
    readonly property bool active: root.visible

    property bool cavaRegistered: false

    function registerCava() {
        if (!cavaRegistered) {
            cavaRegistered = true;
            Cava.registerConsumer();
        }
    }

    function unregisterCava() {
        if (cavaRegistered) {
            cavaRegistered = false;
            Cava.unregisterConsumer();
        }
    }

    function s(val) {
        return Scaler.s(val);
    }

    function formatTime(sec) {
        sec = Math.floor(sec || 0);
        let m = Math.floor(sec / 60), s = sec % 60;
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
    }
=======
    property alias maskRectOuter: borderLayer.maskRectOuter
    property alias chargeAnim: borderLayer.chargeAnim
    property alias bottomSectionSwitch: bottomHeader.bottomSectionSwitch
    property alias balanceSlider: audioView.balanceSlider
    property alias toAudioAnim: toAudioAnim
    property alias toEqAnim: toEqAnim
    property alias toLyricsAnim: toLyricsAnim
    property alias lyricsPickerPopup: lyricsPickerPopup
>>>>>>> upstream Ryoku 1.8.2 (fb5f2c2)

    property var exitCallback: null

    function startExit(onFinished) {
        introAnim.stop();
        chargeAnim.stop();
        exitCallback = onFinished;
        exitAnim.restart();
    }

    function resetAndPlayIntro() {
        exitAnim.stop();
        introMain = 0;
        introCover = 0;
        introText = 0;
        introControls = 0;
        introSeparator = 0;
        introEqHeader = 0;
        introEqSliders = 0;
        introPresets = 0;
        maskRectOuter.drawProgress = 0;
        introAnim.restart();
        chargeAnim.restart();
        if (bottomSectionSwitch.currentIndex === 1) playAudioIntro();
    }

    property bool lyricsSubscribed: false

    function updateLyricsSubscription() {
        let shouldSub = popupRoot.active && (bottomSectionSwitch.currentIndex === 2);
        if (shouldSub && !lyricsSubscribed) {
            lyricsSubscribed = true;
            Lyrics.customPlayer = popupRoot.targetPlayer;
            Lyrics.subscribe();
        } else if (!shouldSub && lyricsSubscribed) {
            lyricsSubscribed = false;
            Lyrics.customPlayer = null;
            Lyrics.unsubscribe();
        } else if (shouldSub && lyricsSubscribed) {
            Lyrics.customPlayer = popupRoot.targetPlayer;
        }
    }

    Shortcut {
        sequence: "Tab"
        enabled: popupRoot.active
        onActivated: {
            bottomSectionSwitch.currentIndex = (bottomSectionSwitch.currentIndex + 1) % 3;
            popupRoot.updateLyricsSubscription();
        }
    }

    Shortcut {
        sequence: "Backtab"
        enabled: popupRoot.active
        onActivated: {
            bottomSectionSwitch.currentIndex = (bottomSectionSwitch.currentIndex + 2) % 3;
            popupRoot.updateLyricsSubscription();
        }
    }

    onActiveChanged: {
        updateLyricsSubscription();
        if (active) {
            forceActiveFocus();
            resetAndPlayIntro();
            registerCava();
            triggerLocalArtFetch();
        } else {
            exitAnim.stop();
            unregisterCava();
            if (lyricsPickerPopup.visible || lyricsPickerPopup.opened) {
                lyricsPickerPopup.closePicker();
            }
            if (popupRoot.eqData && popupRoot.eqData.pending) {
                popupRoot.restoreLastSavedEqualizer();
            }
        }
    }

    Component.onCompleted: {
        if (popupRoot.eqData) {
            popupRoot.savedEqData = Object.assign({}, popupRoot.eqData);
        }
        if (active) {
            forceActiveFocus();
            resetAndPlayIntro();
            registerCava();
            triggerLocalArtFetch();
            updateLyricsSubscription();
        }
    }

    Component.onDestruction: {
        unregisterCava();
        if (lyricsSubscribed) {
            lyricsSubscribed = false;
            Lyrics.unsubscribe();
        }
    }

    Text {
        id: eqMeasureText
        visible: false
        text: popupRoot.eqData && popupRoot.eqData.pending ? (typeof I18n !== "undefined" ? I18n.t("music.eq.apply") : "Apply") : (typeof I18n !== "undefined" ? I18n.t("music.eq.saved") : "Saved")
        font.family: ThemeBackend.fontFamily
        font.pixelSize: popupRoot.s(11.5)
        font.bold: true
    }

    Text {
        id: lyricsMeasureText
        visible: false
        text: typeof I18n !== "undefined" ? I18n.t("music.select_local_file", "Select file") : "Select file"
        font.family: ThemeBackend.fontFamily
        font.pixelSize: popupRoot.s(11.5)
        font.bold: true
    }

    Text {
        id: resetMeasureText
        visible: false
        text: typeof I18n !== "undefined" ? I18n.t("music.audio.reset", "Reset") : "Reset"
        font.family: ThemeBackend.fontFamily
        font.pixelSize: popupRoot.s(11.5)
        font.bold: true
    }

    Text {
        id: testMeasureText
        visible: false
        text: popupRoot.audioTestRunning
            ? (typeof I18n !== "undefined" ? I18n.t("music.audio.stop_test", "Stop") : "Stop")
            : (typeof I18n !== "undefined" ? I18n.t("music.audio.test", "Test") : "Test")
        font.family: ThemeBackend.fontFamily
        font.pixelSize: popupRoot.s(11.5)
        font.bold: true
    }

    property real actionBtnMorph: 0.0
    property real audioHeaderProgress: 0.0
    property real presetSlideProgress: 0.0

    readonly property real eqActionBtnWidth: Math.max(popupRoot.s(68), eqMeasureText.implicitWidth + popupRoot.s(26))
    readonly property real audioActionBtnWidth: Math.max(popupRoot.s(84), resetMeasureText.implicitWidth + popupRoot.s(46))
    readonly property real audioTestBtnWidth: Math.max(popupRoot.s(64), Math.min(popupRoot.s(82), testMeasureText.implicitWidth + popupRoot.s(34)))
    readonly property real lyricsActionBtnWidth: Math.max(popupRoot.s(116), lyricsMeasureText.implicitWidth + popupRoot.s(44))
    readonly property real actionBtnCurrentWidth: actionBtnMorph <= 1.0
        ? eqActionBtnWidth + (audioActionBtnWidth - eqActionBtnWidth) * actionBtnMorph
        : audioActionBtnWidth + (lyricsActionBtnWidth - audioActionBtnWidth) * (actionBtnMorph - 1.0)

    ParallelAnimation {
        id: toLyricsAnim
        running: false
        NumberAnimation {
            target: popupRoot
            property: "actionBtnMorph"
            to: 2.0
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: popupRoot
            property: "presetSlideProgress"
            to: 1.0
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: popupRoot
            property: "audioHeaderProgress"
            to: 0.0
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: toAudioAnim
        running: false
        NumberAnimation {
            target: popupRoot
            property: "actionBtnMorph"
            to: 1.0
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: popupRoot
            property: "presetSlideProgress"
            to: 1.0
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: popupRoot
            property: "audioHeaderProgress"
            to: 1.0
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    ParallelAnimation {
        id: toEqAnim
        running: false
        NumberAnimation {
            target: popupRoot
            property: "actionBtnMorph"
            to: 0.0
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: popupRoot
            property: "presetSlideProgress"
            to: 0.0
            duration: 400
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: popupRoot
            property: "audioHeaderProgress"
            to: 0.0
            duration: 250
            easing.type: Easing.OutCubic
        }
    }

    onTargetPlayerChanged: {
        if (targetPlayer) currentLivePosition = targetPlayer.position;
        triggerLocalArtFetch();
        updateLyricsSubscription();
    }

<<<<<<< port (unstable-dev)
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root.hasTargetPlayer && root.targetPlayer.isPlaying
        onTriggered: {
            if (root.targetPlayer) {
                if (typeof root.targetPlayer.positionChanged === "function") {
                    root.targetPlayer.positionChanged();
                }
                root.currentLivePosition = root.targetPlayer.position;
            }
        }
    }

    property string localArtUrl: ""
    property string localBlur: ""
    property string localGrad: ""
    property string localTextColor: ""
    property string localDeviceIcon: "󰓃"
    property string localDeviceName: "Speaker"

    Process {
        id: customArtFetchProc
        command: [
            "bash",
            Caching.payloadDir + "/media/art_fetch.sh",
            root.targetPlayer ? (root.targetPlayer.busName || root.targetPlayer.identity || "") : "",
            root.targetPlayer ? (root.targetPlayer.trackArtUrl || "") : "",
            root.targetPlayer ? (root.targetPlayer.trackTitle || "") : "",
            root.targetPlayer ? (root.targetPlayer.trackArtist || "") : ""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try {
                        let d = JSON.parse(txt);
                        root.localArtUrl = d.artUrl || "";
                        root.localBlur = d.blur || "";
                        root.localGrad = d.grad || "";
                        root.localTextColor = d.textColor || "#cdd6f4";
                        root.localDeviceIcon = d.deviceIcon || "󰓃";
                        root.localDeviceName = d.deviceName || "Speaker";
                    } catch(e) {}
                }
            }
        }
    }

    function triggerLocalArtFetch() {
        if (root.targetPlayer && root.targetPlayer !== MprisController.activePlayer) {
            customArtFetchProc.running = false;
            customArtFetchProc.running = true;
        } else if (root.targetPlayer && root.targetPlayer === MprisController.activePlayer) {
            if (!MprisController.artUrl) {
                MprisController.queueFetch();
            }
        }
    }

    property string activeArtUrl: (targetPlayer && targetPlayer === MprisController.activePlayer) ? MprisController.artUrl : localArtUrl
    property string activeBlur: (targetPlayer && targetPlayer === MprisController.activePlayer) ? MprisController.blur : localBlur
    property string activeGrad: (targetPlayer && targetPlayer === MprisController.activePlayer) ? MprisController.grad : localGrad
    property string activeTextColor: (targetPlayer && targetPlayer === MprisController.activePlayer) ? MprisController.textColor : (localTextColor || "#cdd6f4")
    property string activeDeviceIcon: (targetPlayer && targetPlayer === MprisController.activePlayer) ? MprisController.deviceIcon : localDeviceIcon
    property string activeDeviceName: (targetPlayer && targetPlayer === MprisController.activePlayer) ? MprisController.deviceName : localDeviceName

    property var eqData: {
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false, "balance": 0,
        "mono": false, "swap": false, "dynamics": "off"
    }

    property var savedEqData: ({
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false, "balance": 0,
        "mono": false, "swap": false, "dynamics": "off"
    })

    property bool audioTestRunning: false

    Timer {
        id: audioTestTimer
        interval: 3200
        repeat: false
        onTriggered: root.audioTestRunning = false
    }

    function restoreLastSavedEqualizer() {
        if (!root.savedEqData) return;
        var wasPending = root.eqData && root.eqData.pending;
        var needsRestore = wasPending;
        if (!needsRestore && root.eqData) {
            for (var i = 1; i <= 10; i++) {
                if (root.eqData["b" + i] !== root.savedEqData["b" + i]) {
                    needsRestore = true;
                    break;
                }
            }
        }
        var restored = Object.assign({}, root.savedEqData);
        restored.pending = false;
        root.eqData = restored;
        if (needsRestore) {
            root.lastEqUpdate = Date.now();
            if (root.savedEqData.preset && root.savedEqData.preset !== "Custom") {
                root.execCmd(Caching.payloadDir + `/media/equalizer.sh preset ${root.savedEqData.preset}`);
            } else {
                for (var b = 1; b <= 10; b++) {
                    if (root.savedEqData["b" + b] !== undefined) {
                        root.execCmd(Caching.payloadDir + `/media/equalizer.sh set_band ${b} ${root.savedEqData["b" + b]}`);
                    }
                }
            }
        }
    }

    property color eqAccentColor: ThemeBackend.mauve || "#cba6f7"
    property string accumulatedEqOut: ""
    property real lastEqUpdate: 0

    property real eqLightningProgress: 0.0
    property real eqLightningFade: 1.0

    SequentialAnimation {
        id: eqLightningAnim
        running: false
        ScriptAction { script: { root.eqLightningFade = 0.0; root.eqLightningProgress = 0.0; } }
        NumberAnimation {
            target: root; property: "eqLightningProgress";
            from: 0.0; to: 10.0;
            duration: 650;
            easing.type: Easing.OutSine
        }
        PauseAnimation { duration: 150 }
        NumberAnimation {
            target: root; property: "eqLightningFade";
            from: 0.0; to: 1.0;
            duration: 800;
            easing.type: Easing.OutQuad
        }
        ScriptAction { script: { root.eqLightningProgress = 0.0; } }
    }

    function triggerEqLightning() {
        Sounds.playSfx("musicpopup/swoosh.wav", 0.75);
        eqLightningAnim.restart();
    }

=======
>>>>>>> upstream Ryoku 1.8.2 (fb5f2c2)
    property real introMain: 0
    property real introCover: 0
    property real introText: 0
    property real introControls: 0
    property real introSeparator: 0
    property real introEqHeader: 0
    property real introEqSliders: 0
    property real introPresets: 0
    property real audioIntroBalance: 0
    property real audioIntroFlags: 0
    property real audioIntroDynamics: 0

    ParallelAnimation {
        id: audioIntroAnim
        running: false

        NumberAnimation { target: popupRoot; property: "audioIntroBalance"; from: 0; to: 1.0; duration: 560; easing.type: Easing.OutQuart }

        SequentialAnimation {
            PauseAnimation { duration: 70 }
            NumberAnimation { target: popupRoot; property: "audioIntroFlags"; from: 0; to: 1.0; duration: 560; easing.type: Easing.OutQuart }
        }

        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: popupRoot; property: "audioIntroDynamics"; from: 0; to: 1.0; duration: 560; easing.type: Easing.OutQuart }
        }
    }

    function playAudioIntro() {
        audioIntroBalance = 0;
        audioIntroFlags = 0;
        audioIntroDynamics = 0;
        audioIntroAnim.restart();
    }

    ParallelAnimation {
        id: introAnim
        running: false

        NumberAnimation { target: popupRoot; property: "introMain"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutQuart }

        SequentialAnimation {
            PauseAnimation { duration: 70 }
            NumberAnimation { target: popupRoot; property: "introCover"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: popupRoot; property: "introText"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutQuart }
        }

        SequentialAnimation {
            PauseAnimation { duration: 230 }
            NumberAnimation { target: popupRoot; property: "introControls"; from: 0; to: 1.0; duration: 760; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }

        SequentialAnimation {
            PauseAnimation { duration: 310 }
            NumberAnimation { target: popupRoot; property: "introSeparator"; from: 0; to: 1.0; duration: 660; easing.type: Easing.OutQuart }
        }

        SequentialAnimation {
            PauseAnimation { duration: 370 }
            NumberAnimation { target: popupRoot; property: "introEqHeader"; from: 0; to: 1.0; duration: 710; easing.type: Easing.OutQuart }
        }

        SequentialAnimation {
            PauseAnimation { duration: 430 }
            NumberAnimation { target: popupRoot; property: "introEqSliders"; from: 0; to: 1.0; duration: 860; easing.type: Easing.OutExpo }
        }

        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: popupRoot; property: "introPresets"; from: 0; to: 1.0; duration: 810; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    SequentialAnimation {
        id: exitAnim
        running: false
        ParallelAnimation {
            NumberAnimation { target: popupRoot; property: "introPresets"; to: 0.0; duration: 130; easing.type: Easing.InBack }
            NumberAnimation { target: popupRoot; property: "introEqSliders"; to: 0.0; duration: 150; easing.type: Easing.InExpo }
            SequentialAnimation {
                PauseAnimation { duration: 30 }
                NumberAnimation { target: popupRoot; property: "introEqHeader"; to: 0.0; duration: 130; easing.type: Easing.InCubic }
                NumberAnimation { target: popupRoot; property: "introSeparator"; to: 0.0; duration: 130; easing.type: Easing.InCubic }
            }
            SequentialAnimation {
                PauseAnimation { duration: 50 }
                NumberAnimation { target: popupRoot; property: "introControls"; to: 0.0; duration: 150; easing.type: Easing.InBack }
                NumberAnimation { target: popupRoot; property: "introText"; to: 0.0; duration: 150; easing.type: Easing.InCubic }
                NumberAnimation { target: popupRoot; property: "introCover"; to: 0.0; duration: 150; easing.type: Easing.InBack }
            }
            SequentialAnimation {
                PauseAnimation { duration: 70 }
                NumberAnimation { target: popupRoot; property: "introMain"; to: 0.0; duration: 170; easing.type: Easing.InQuart }
            }
        }
        ScriptAction {
            script: {
                if (popupRoot.exitCallback) {
                    let cb = popupRoot.exitCallback;
                    popupRoot.exitCallback = null;
                    cb();
                }
            }
        }
    }

<<<<<<< port (unstable-dev)
    property var borderColors: {
        var defaultColors = [ThemeBackend.mauve || "#cba6f7", ThemeBackend.blue || "#89b4fa", ThemeBackend.red || "#f38ba8", ThemeBackend.mauve || "#cba6f7"];
        var gradSource = root.activeGrad || (typeof MprisController !== "undefined" ? MprisController.grad : "");
        if (!gradSource) return defaultColors;

        var hexRegex = /#[0-9a-fA-F]{6}/g;
        var matches = gradSource.match(hexRegex);

        if (matches && matches.length >= 3) {
            return [matches[0], matches[1], matches[2], matches[0]];
        }
        return defaultColors;
    }

    property color bc1: borderColors[0] || ThemeBackend.mauve || "#cba6f7"
    property color bc2: borderColors[1] || ThemeBackend.blue || "#89b4fa"
    property color bc3: borderColors[2] || ThemeBackend.red || "#f38ba8"
    property color bc4: borderColors[3] || ThemeBackend.mauve || "#cba6f7"

    property color dynamicTextColor: {
        var rawCol = root.activeTextColor || (typeof MprisController !== "undefined" ? MprisController.textColor : "");
        if (rawCol) {
            var c = String(rawCol).trim();
            var match = c.match(/^(#[0-9a-fA-F]{6})/);
            if (match) return match[1];
        }
        return ThemeBackend.text || "#cdd6f4";
    }

    function execCmd(cmdStr) {
        var safeCmd = cmdStr.replace(/`/g, "\\`");
        var p = Qt.createQmlObject(`
            import Quickshell.Io
            Process {
                command: ["bash", "-c", \`${safeCmd}\`]
                running: true
                onExited: (exitCode) => destroy()
            }
        `, root);
    }

    function applyPresetOptimistically(presetName) {
        var presets = {
            "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "Bass": [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
            "Treble": [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
            "Vocal": [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
            "Pop": [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
            "Rock": [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
            "Jazz": [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
            "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4]
        };
        if (presets[presetName]) {
            var temp = Object.assign({}, root.eqData);
            for (var i = 0; i < 10; i++) {
                temp["b" + (i + 1)] = presets[presetName][i];
            }
            temp.preset = presetName;
            temp.pending = false;
            root.eqData = temp;
            root.savedEqData = Object.assign({}, temp);

            root.lastEqUpdate = Date.now();

            root.triggerEqLightning();
            execCmd(Caching.payloadDir + `/media/equalizer.sh preset ${presetName}`);
        }
    }

    function setBalance(value) {
        var clamped = Math.max(-1.0, Math.min(1.0, Number(value)));
        if (isNaN(clamped)) return;

        var temp = Object.assign({}, root.eqData);
        temp.balance = Math.round(clamped * 100) / 100;
        root.eqData = temp;
        root.savedEqData = Object.assign({}, temp);
        root.lastEqUpdate = Date.now();
        root.execCmd(Caching.payloadDir + `/media/equalizer.sh set_balance ${temp.balance}`);
    }

    function setAudioFlag(name, value) {
        if (name !== "mono" && name !== "swap") return;
        var temp = Object.assign({}, root.eqData);
        temp[name] = value === true;
        root.eqData = temp;
        root.savedEqData = Object.assign({}, temp);
        root.lastEqUpdate = Date.now();
        root.execCmd(Caching.payloadDir + `/media/equalizer.sh set_${name} ${temp[name]}`);
    }

    function setDynamics(value) {
        if (["off", "balanced", "night"].indexOf(value) < 0) return;
        var temp = Object.assign({}, root.eqData);
        temp.dynamics = value;
        root.eqData = temp;
        root.savedEqData = Object.assign({}, temp);
        root.lastEqUpdate = Date.now();
        root.execCmd(Caching.payloadDir + `/media/equalizer.sh set_dynamics ${value}`);
    }

    function resetAudio() {
        var temp = Object.assign({}, root.eqData);
        temp.balance = 0;
        temp.mono = false;
        temp.swap = false;
        temp.dynamics = "off";
        root.eqData = temp;
        root.savedEqData = Object.assign({}, temp);
        root.audioTestRunning = false;
        audioTestTimer.stop();
        root.lastEqUpdate = Date.now();
        root.execCmd(Caching.payloadDir + "/media/equalizer.sh reset_audio");
    }

    function toggleAudioTest() {
        if (root.audioTestRunning) {
            root.execCmd(Caching.payloadDir + "/media/equalizer.sh stop_test");
            root.audioTestRunning = false;
            audioTestTimer.stop();
        } else {
            root.execCmd(Caching.payloadDir + "/media/equalizer.sh test");
            root.audioTestRunning = true;
            audioTestTimer.restart();
        }
    }

    property bool eqInitDone: false

    function applyEqState(text) {
        var outStr = text ? text.trim() : "";
        if (outStr.length === 0) return;

        // Our own writes land here too; skip them for a moment and re-read once they settle.
        var sinceLocal = Date.now() - root.lastEqUpdate;
        if (sinceLocal < 2000) {
            eqResyncTimer.interval = 2000 - sinceLocal;
            eqResyncTimer.restart();
            return;
        }

        try {
            var parsed = JSON.parse(outStr);
            root.eqData = parsed;
            if (!parsed.pending) {
                root.savedEqData = Object.assign({}, parsed);
            }
        } catch(e) {}
    }

    // equalizer.sh keeps its state in this file; watch it instead of polling the script.
    FileView {
        id: eqStateFile
        path: Caching.runDir + "/music/eq_state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyEqState(text())
        // The script creates the file with defaults on first use.
        onLoadFailed: {
            if (!root.eqInitDone && !eqInitProc.running) {
                root.eqInitDone = true;
                eqInitProc.running = true;
            }
        }
    }

    Timer {
        id: eqResyncTimer
        repeat: false
        onTriggered: eqStateFile.reload()
    }

    Process {
        id: eqInitProc
        running: false
        command: ["bash", "-c", Caching.payloadDir + "/media/equalizer.sh get"]
        onExited: eqStateFile.reload()
    }

=======
>>>>>>> upstream Ryoku 1.8.2 (fb5f2c2)
    LyricsPicker {
        id: lyricsPickerPopup
        targetScreen: (popupRoot.Window && popupRoot.Window.window) ? popupRoot.Window.window.screen : null
        onLyricsSelected: function(filePath, fileName) {
            Lyrics.loadLocalLyricsFile(filePath);
        }
    }

    Item {
        id: mainWrapper
        anchors.fill: parent
<<<<<<< port (unstable-dev)

        scale: 0.92 + (0.08 * root.introMain)
        opacity: root.introMain
        transform: Translate { y: root.s(12) * (1 - root.introMain) }

        Item {
            anchors.fill: parent
            visible: !ThemeBackend.liquidGlass

            Shape {
                id: maskRectOuter
                anchors.fill: parent
                visible: false
                layer.enabled: true
                preferredRendererType: Shape.GeometryRenderer

                property real sw: root.s(6)
                property real inset: (sw / 2) + root.s(0.5)
                property real w: width
                property real h: height
                property real r: ThemeBackend.borderRadius - inset

                property real straightLines: 2 * (w - 2 * inset - 2 * r) + 2 * (h - 2 * inset - 2 * r)
                property real arcLines: 2 * Math.PI * r
                property real perimeter: straightLines + arcLines

                property real drawProgress: 0

                NumberAnimation on drawProgress {
                    id: chargeAnim
                    from: 0
                    to: maskRectOuter.perimeter
                    duration: 1200
                    easing.type: Easing.OutCubic
                    running: false
                }

                ShapePath {
                    strokeWidth: maskRectOuter.sw
                    strokeColor: "black"
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap

                    dashPattern: [maskRectOuter.perimeter / maskRectOuter.sw, maskRectOuter.perimeter / maskRectOuter.sw]
                    dashOffset: (maskRectOuter.perimeter - maskRectOuter.drawProgress) / maskRectOuter.sw

                    startX: maskRectOuter.inset
                    startY: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r

                    PathLine { x: maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r }
                    PathArc {
                        x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.inset
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise
                    }
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.inset }
                    PathArc {
                        x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise
                    }
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r }
                    PathArc {
                        x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise
                    }
                    PathLine { x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset }
                    PathArc {
                        x: maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise
                    }
                }
            }

            Item {
                id: gradContainer
                anchors.fill: parent
                visible: false
                opacity: ThemeBackend.elementOpacity
                clip: true

                Rectangle {
                    width: Math.max(parent.width, parent.height) * 2
                    height: width
                    anchors.centerIn: parent

                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: 5000
                        loops: Animation.Infinite
                        running: root.active
                    }

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: root.bc1; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.33; color: root.bc2; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.66; color: root.bc3; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 1.0; color: root.bc4; Behavior on color { ColorAnimation { duration: 800; easing.type: Easing.InOutQuad } } }
                    }
                }
            }

            MultiEffect {
                source: gradContainer
                anchors.fill: parent
                maskEnabled: true
                maskSource: maskRectOuter
            }
=======
        
        scale: 0.92 + (0.08 * popupRoot.introMain)
        opacity: popupRoot.introMain
        transform: Translate { y: popupRoot.s(12) * (1 - popupRoot.introMain) }

        MusicBorder {
            id: borderLayer
            root: popupRoot
>>>>>>> upstream Ryoku 1.8.2 (fb5f2c2)
        }

        Rectangle {
            id: innerBg
            anchors.fill: parent
            anchors.margins: ThemeBackend.liquidGlass ? 0 : popupRoot.s(3)
            color: Qt.alpha(ThemeBackend.base, ThemeBackend.elementOpacity)
            radius: ThemeBackend.borderRadius

            WallpaperBlur {
                z: -1
                anchors.fill: parent
                radius: parent.radius
            }

            Rectangle {
                id: innerBgMask
                anchors.fill: parent
                radius: ThemeBackend.borderRadius
                visible: false
                layer.enabled: true
            }

            Item {
                id: bgEffectsLayer
                anchors.fill: parent

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: innerBgMask
                }

                MusicBlurCrossfader {
                    root: popupRoot
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: popupRoot.s(18)
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: popupRoot.s(224)
                    spacing: popupRoot.s(16)

<<<<<<< port (unstable-dev)
                    Item {
                        id: coverHost
                        Layout.preferredWidth: root.s(224)
                        Layout.preferredHeight: root.s(224)
                        Layout.alignment: Qt.AlignVCenter

                        opacity: root.introCover
                        transform: Translate { x: root.s(-35) * (1 - root.introCover); y: root.s(9) * (1 - root.introCover) }

                        property real availableRadius: width / 2
                        property real dynMargin: 0
                        property real artRadius: availableRadius * 0.86
                        property real maxBarHeight: availableRadius - artRadius
                        property real barWidth: Math.max(root.s(2), (2 * Math.PI * artRadius) / root.barCount * 0.65)

                        Item {
                            id: discAndVisGroup
                            anchors.centerIn: parent
                            width: coverHost.artRadius * 2
                            height: coverHost.artRadius * 2

                            property real targetScale: (root.targetPlayer && root.targetPlayer.isPlaying) ? (1.0 + (root.bassLevel * 0.0135) + (root.kickLevel * 0.027)) : 0.90
                            property real targetBounceY: (root.targetPlayer && root.targetPlayer.isPlaying) ? -(root.kickLevel * coverHost.artRadius * 0.02025) : 0
                            property real targetTilt: (root.targetPlayer && root.targetPlayer.isPlaying) ? (root.bassLevel - 0.3) * 0.9 : 0

                            anchors.verticalCenterOffset: targetBounceY
                            rotation: targetTilt
                            scale: targetScale

                            Behavior on anchors.verticalCenterOffset {
                                SpringAnimation {
                                    spring: 4.8
                                    damping: 0.38
                                    mass: 0.85
                                }
                            }

                            Behavior on rotation {
                                SpringAnimation {
                                    spring: 2.8
                                    damping: 0.52
                                    mass: 0.95
                                }
                            }

                            Behavior on scale {
                                SpringAnimation {
                                    spring: 5.2
                                    damping: 0.35
                                    mass: 0.75
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: (coverHost.artRadius * 2) + (coverHost.maxBarHeight * 2.2)
                                height: width
                                radius: width / 2
                                color: ThemeBackend.mauve || "#cba6f7"
                                opacity: (root.targetPlayer && root.targetPlayer.isPlaying) ? (0.005 + (root.bassLevel * 0.035)) : 0.0
                                scale: 0.985 + (root.bassLevel * 0.0375)

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 120
                                        easing.type: Easing.OutQuad
                                    }
                                }
                                Behavior on scale {
                                    SpringAnimation {
                                        spring: 4.2
                                        damping: 0.38
                                        mass: 0.8
                                    }
                                }
                            }

                            Rectangle {
                                anchors.centerIn: parent
                                width: (coverHost.artRadius * 2) + (coverHost.maxBarHeight * 1.5)
                                height: width
                                radius: width / 2
                                color: ThemeBackend.mauve || "#cba6f7"
                                opacity: (root.targetPlayer && root.targetPlayer.isPlaying) ? (0.01 + (root.kickLevel * 0.055)) : 0.0
                                scale: 0.992 + (root.kickLevel * 0.02625)

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 40
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                Behavior on scale {
                                    SpringAnimation {
                                        spring: 5.2
                                        damping: 0.34
                                        mass: 0.6
                                    }
                                }
                            }

                            Visualizer {
                                anchors.centerIn: parent
                                width: (coverHost.artRadius + coverHost.maxBarHeight * 1.4) * 2 + 2
                                height: width
                                active: root.cavaRegistered
                                count: root.barCount
                                color: ThemeBackend.mauve || "#cba6f7"
                                mirrored: false
                                curve: 1.15
                                threshold: 0.0
                                gamma: 1.08
                                rise: 0.55
                                fall: 0.55
                                ringRadius: coverHost.artRadius
                                ringBarWidth: coverHost.barWidth
                                maxLength: coverHost.maxBarHeight * 1.4
                                minLength: root.s(2)
                                opacityBase: 0.4
                                opacityRange: 0.6
                                tintStrength: 0.45
                            }

                            Item {
                                id: discContainer
                                anchors.fill: parent

                                property real borderWidth: 0

                                Rectangle {
                                    z: -1
                                    anchors.centerIn: parent
                                    width: parent.width + root.s(12)
                                    height: parent.height + root.s(12)
                                    radius: width / 2
                                    color: ThemeBackend.mauve || "#cba6f7"
                                    opacity: (root.targetPlayer && root.targetPlayer.isPlaying) ? (0.35 + root.kickLevel * 0.25) : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 500 } }
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        blurEnabled: true
                                        blurMax: 32
                                        blur: 1.0
                                    }
                                }

                                Rectangle {
                                    id: vinylBase
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: ThemeBackend.surface1 || "#45475a"
                                    border.width: discContainer.borderWidth
                                    border.color: (root.targetPlayer && root.targetPlayer.isPlaying) ? (ThemeBackend.mauve || "#cba6f7") : (ThemeBackend.overlay0 || "#6c7086")
                                    Behavior on border.color { ColorAnimation { duration: 500 } }

                                    NumberAnimation on rotation {
                                        from: 0; to: 360; duration: 25000
                                        loops: Animation.Infinite
                                        running: root.active && root.targetPlayer && root.targetPlayer.isPlaying
                                    }

                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: vinylBase.border.width

                                        Rectangle {
                                            id: maskRect
                                            anchors.fill: parent
                                            radius: width / 2
                                            visible: false
                                            layer.enabled: true
                                        }

                                        Item {
                                            id: artMaskedContainer
                                            anchors.fill: parent
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: maskRect
                                            }

                                            Item {
                                                id: artCrossfader
                                                anchors.fill: parent
                                                property string artSource: root.activeArtUrl ? (root.activeArtUrl.startsWith("file://") || root.activeArtUrl.startsWith("http") ? root.activeArtUrl : "file://" + root.activeArtUrl) : ""
                                                property bool showingA: true

                                                Image {
                                                    id: artImgA
                                                    anchors.fill: parent
                                                    fillMode: Image.PreserveAspectCrop
                                                    opacity: artCrossfader.showingA && status === Image.Ready ? 1.0 : 0.0
                                                    Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutQuad } }
                                                }

                                                Image {
                                                    id: artImgB
                                                    anchors.fill: parent
                                                    fillMode: Image.PreserveAspectCrop
                                                    opacity: !artCrossfader.showingA && status === Image.Ready ? 1.0 : 0.0
                                                    Behavior on opacity { NumberAnimation { duration: 650; easing.type: Easing.InOutQuad } }
                                                }

                                                onArtSourceChanged: {
                                                    if (!artSource) {
                                                        artImgA.source = "";
                                                        artImgB.source = "";
                                                        return;
                                                    }
                                                    if (showingA) {
                                                        artImgB.source = artSource;
                                                        showingA = false;
                                                    } else {
                                                        artImgA.source = artSource;
                                                        showingA = true;
                                                    }
                                                }

                                                Component.onCompleted: {
                                                    if (artSource) {
                                                        artImgA.source = artSource;
                                                        showingA = true;
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            id: fallbackPlaceholder
                                            anchors.fill: parent
                                            radius: width / 2
                                            color: ThemeBackend.mantle || "#1e1e2e"
                                            opacity: (root.hasTargetPlayer && root.activeArtUrl) ? 0.0 : 1.0
                                            Behavior on opacity { NumberAnimation { duration: 400 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "󰝚"
                                                font.pixelSize: parent.width * 0.26
                                                color: ThemeBackend.overlay1 || "#7f849c"
                                            }
                                        }

                                        Rectangle {
                                            id: discTinter
                                            anchors.fill: parent
                                            radius: width / 2
                                            color: {
                                                let m = ThemeBackend.mauve || Qt.rgba(0.8, 0.6, 0.9, 1);
                                                return Qt.rgba(m.r, m.g, m.b, 0.08 + (root.kickLevel * 0.08));
                                            }
                                            opacity: (root.hasTargetPlayer && root.activeArtUrl) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 600 } }
                                        }

                                        Repeater {
                                            model: [0.92, 0.84, 0.76, 0.68, 0.60, 0.52, 0.44]
                                            delegate: Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width * modelData
                                                height: width
                                                radius: width / 2
                                                color: "transparent"
                                                border.color: index % 2 === 0 ? "#ffffff" : "#000000"
                                                border.width: 1
                                                opacity: (index % 2 === 0 ? 0.035 : 0.06) + (root.bassLevel * 0.02)
                                                antialiasing: true
                                            }
                                        }

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width * 0.28
                                            height: width
                                            radius: width / 2
                                            color: ThemeBackend.crust || "#11111b"
                                            opacity: 0.96
                                            scale: 1.0 + (root.kickLevel * 0.0135)
                                            border.width: 1.5
                                            border.color: {
                                                let m = ThemeBackend.mauve || Qt.rgba(0.8, 0.6, 0.9, 1);
                                                return Qt.rgba(m.r, m.g, m.b, 0.45 + (root.kickLevel * 0.4));
                                            }

                                            Behavior on scale {
                                                SpringAnimation {
                                                    spring: 6.0
                                                    damping: 0.32
                                                    mass: 0.5
                                                }
                                            }

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: parent.width * 0.68
                                                height: width
                                                radius: width / 2
                                                color: ThemeBackend.surface2 || "#585b70"
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.18)

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: parent.width * 0.38
                                                    height: width
                                                    radius: width / 2
                                                    color: "#0d0e15"
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        Layout.topMargin: -root.s(14)
                        spacing: root.s(12)

                        ColumnLayout {
                            z: 1
                            spacing: root.s(6)
                            opacity: root.introText
                            transform: Translate { x: root.s(25) * (1 - root.introText) }

                            MarqueeText {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(25)
                                text: (root.targetPlayer && root.targetPlayer.trackTitle !== "") ? root.targetPlayer.trackTitle : I18n.t("music.nothing_playing")
                                color: root.dynamicTextColor
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(19)
                                font.bold: true
                                marqueeSpacing: root.s(50)
                                speed: 25
                                active: root.active

                                Behavior on color { ColorAnimation { duration: 600 } }
                            }

                            Text {
                                text: root.targetPlayer && root.targetPlayer.trackArtist ? I18n.t("music.by_artist", { "artist": root.targetPlayer.trackArtist }) : I18n.t("music.by_artist", { "artist": I18n.t("music.unknown_artist") })
                                color: root.dynamicTextColor
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(13.5)
                                font.bold: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(18)
                            }
                            RowLayout {
                                spacing: root.s(9)
                                ClickButton {
                                    id: devicePill
                                    Layout.preferredHeight: root.s(22)
                                    cornerRadius: ThemeBackend.borderRadius
                                    horizontalPadding: root.s(10)
                                    buttonText: (root.activeDeviceIcon || "󰓃") + " " + (root.activeDeviceName || I18n.t("music.speaker"))
                                    textFontSize: root.s(11.5)
                                    accentColor: ThemeBackend.surface0 || "#313244"
                                    bgOpacity: ThemeBackend.elementOpacity
                                    textColor: ThemeBackend.text || "#cdd6f4"
                                }
                                Dropdown {
                                    id: sourceDropdown
                                    visible: root.playerList.length >= 2
                                    Layout.preferredHeight: root.s(22)
                                    implicitHeight: root.s(22)
                                    implicitWidth: root.s(140)
                                    cornerRadius: ThemeBackend.borderRadius
                                    options: root.playerOptions
                                    currentIndex: root.currentPlayerIndex
                                    fontPixelSize: root.s(11.5)
                                    iconSize: root.s(12)
                                    accentColor: ThemeBackend.mauve || "#cba6f7"
                                    baseColor: Qt.alpha(ThemeBackend.surface0 || "#313244", ThemeBackend.elementOpacity)
                                    hoverColor: ThemeBackend.surface1 || "#45475a"
                                    dropdownColor: ThemeBackend.surface0
                                    borderColor: Qt.alpha(ThemeBackend.surface2 || "#585b70", 0.6)
                                    textColor: ThemeBackend.text || "#cdd6f4"
                                    activeTextColor: ThemeBackend.crust || "#11111b"
                                    onValueChanged: (index, value) => {
                                        root.selectPlayerByIndex(index);
                                    }
                                }
                                ClickButton {
                                    id: sourcePill
                                    visible: root.playerList.length < 2
                                    Layout.preferredHeight: root.s(22)
                                    cornerRadius: ThemeBackend.borderRadius
                                    horizontalPadding: root.s(10)
                                    buttonText: I18n.t("music.via_source", { "source": root.targetPlayer ? (root.targetPlayer.identity || root.targetPlayer.desktopEntry || "Media") : I18n.t("music.offline") })
                                    textFontSize: root.s(11.5)
                                    accentColor: ThemeBackend.surface0 || "#313244"
                                    bgOpacity: ThemeBackend.elementOpacity
                                    textColor: ThemeBackend.subtext0 || "#9399b2"
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: -root.s(6)
                            spacing: root.s(2)
                            opacity: root.introControls
                            transform: Translate { x: root.s(18) * (1 - root.introControls); y: root.s(9) * (1 - root.introControls) }

                            WavySeekBar {
                                id: progBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(50)
                                Layout.topMargin: -root.s(16)
                                Layout.bottomMargin: -root.s(2)
                                Layout.alignment: Qt.AlignVCenter
                                from: 0.0
                                to: root.targetPlayer ? root.targetPlayer.length : 100.0
                                value: root.currentLivePosition
                                playing: root.targetPlayer ? root.targetPlayer.isPlaying : false
                                waveColor: ThemeBackend.mauve || "#cba6f7"

                                property bool seekPending: false

                                Timer {
                                    id: seekTimer
                                    interval: 1000
                                    onTriggered: progBar.seekPending = false
                                }

                                Connections {
                                    target: root.targetPlayer
                                    function onPositionChanged() {
                                        if (!root.active) return;
                                        if (!progBar.isDragging && !progBar.seekPending && root.targetPlayer) {
                                            progBar.value = root.targetPlayer.position;
                                        }
                                    }
                                }

                                onMoved: val => {
                                    if (root.targetPlayer && root.targetPlayer.canSeek) {
                                        progBar.seekPending = true;
                                        seekTimer.restart();
                                        progBar.value = val;
                                        root.targetPlayer.position = val;
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: root.formatTime(root.currentLivePosition);
                                    color: root.dynamicTextColor;
                                    font.family: ThemeBackend.fontFamily;
                                    font.bold: true;
                                    font.pixelSize: root.s(12);
                                    Behavior on color { ColorAnimation { duration: 600 } }
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.formatTime(root.targetPlayer ? root.targetPlayer.length : 0);
                                    color: root.dynamicTextColor;
                                    font.family: ThemeBackend.fontFamily;
                                    font.bold: true;
                                    font.pixelSize: root.s(12);
                                    Behavior on color { ColorAnimation { duration: 600 } }
                                }
                            }
                        }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: root.s(18)
                            opacity: root.introControls
                            transform: Translate { y: root.s(18) * (1 - root.introControls) }

                            IconButton {
                                id: prevMediaBtn
                                Layout.preferredWidth: root.s(32)
                                Layout.preferredHeight: root.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰒮"
                                iconFontSize: root.s(11)
                                accentColor: ThemeBackend.surface0 || "#313244"
                                bgOpacity: ThemeBackend.liquidGlass ? 1.0 : ThemeBackend.elementOpacity
                                textColor: isHoveredOrHighlighted ? (ThemeBackend.text || "#cdd6f4") : (ThemeBackend.subtext0 || "#a6adc8")
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: if (root.targetPlayer && root.targetPlayer.canGoPrevious) root.targetPlayer.previous()
                            }

                            IconButton {
                                id: playPauseBtn
                                Layout.preferredWidth: root.s(43)
                                Layout.preferredHeight: root.s(43)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: (root.targetPlayer && root.targetPlayer.isPlaying) ? "󰏤" : "󰐊"
                                iconFontSize: root.s(15)
                                accentColor: ThemeBackend.surface0 || "#313244"
                                bgOpacity: ThemeBackend.liquidGlass ? 1.0 : ThemeBackend.elementOpacity
                                textColor: isHoveredOrHighlighted ? (ThemeBackend.mauve || "#cba6f7") : (ThemeBackend.text || "#cdd6f4")
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: if (root.targetPlayer && root.targetPlayer.canTogglePlaying) root.targetPlayer.togglePlaying()
                            }

                            IconButton {
                                id: nextMediaBtn
                                Layout.preferredWidth: root.s(32)
                                Layout.preferredHeight: root.s(32)
                                cornerRadius: ThemeBackend.borderRadius
                                buttonIcon: "󰒭"
                                iconFontSize: root.s(11)
                                accentColor: ThemeBackend.surface0 || "#313244"
                                bgOpacity: ThemeBackend.liquidGlass ? 1.0 : ThemeBackend.elementOpacity
                                textColor: isHoveredOrHighlighted ? (ThemeBackend.text || "#cdd6f4") : (ThemeBackend.subtext0 || "#a6adc8")
                                Layout.alignment: Qt.AlignVCenter
                                onClicked: if (root.targetPlayer && root.targetPlayer.canGoNext) root.targetPlayer.next()
                            }
                        }
=======
                    MusicCover {
                        root: popupRoot
                    }

                    MusicTrackControls {
                        root: popupRoot
>>>>>>> upstream Ryoku 1.8.2 (fb5f2c2)
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: popupRoot.s(2)
                    Layout.topMargin: popupRoot.s(16)
                    Layout.bottomMargin: popupRoot.s(16)
                    color: "#1AFFFFFF"
                    radius: popupRoot.s(1)

                    opacity: popupRoot.introSeparator
                    transform: Translate { y: popupRoot.s(12) * (1 - popupRoot.introSeparator) }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: popupRoot.s(12)

                    MusicBottomHeader {
                        id: bottomHeader
                        root: popupRoot
                    }

                    Item {
                        id: bottomViewsContainer
                        Layout.fillWidth: true
                        Layout.preferredHeight: popupRoot.s(235)

<<<<<<< port (unstable-dev)
                        Item {
                            id: eqView
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width
                            x: bottomSectionSwitch.currentIndex === 0 ? 0 : -parent.width - root.s(24)
                            opacity: bottomSectionSwitch.currentIndex === 0 ? 1.0 : 0.0
                            visible: opacity > 0.0

                            Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutQuart } }
                            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: root.s(12)

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: root.s(155)

                                    Row {
                                        id: eqSliderRow
                                        anchors.fill: parent
                                        z: 1

                                        Repeater {
                                            model: [
                                                {"idx": 1, "lbl": "31"}, {"idx": 2, "lbl": "63"}, {"idx": 3, "lbl": "125"},
                                                {"idx": 4, "lbl": "250"}, {"idx": 5, "lbl": "500"}, {"idx": 6, "lbl": "1k"},
                                                {"idx": 7, "lbl": "2k"}, {"idx": 8, "lbl": "4k"}, {"idx": 9, "lbl": "8k"},
                                                {"idx": 10, "lbl": "16k"}
                                            ]
                                            delegate: Item {
                                                id: sliderDelegate
                                                width: eqSliderRow.width / 10
                                                height: eqSliderRow.height

                                                opacity: root.introEqSliders
                                                transform: Translate {
                                                    y: root.s(25) * (1 - root.introEqSliders) + (index * root.s(7) * (1 - root.introEqSliders))
                                                }

                                                property real dist: root.eqLightningProgress - (modelData.idx - 1)
                                                property real hitPulse: dist >= 0 && dist < 1.0 ? Math.sin((dist) * Math.PI) : 0.0

                                                property real trackPulse: 0.0
                                                property real ringPulse: 0.0
                                                property real flashFade: 0.0
                                                property bool hasFired: false

                                                onDistChanged: {
                                                    if (dist <= 0.05) {
                                                        hasFired = false;
                                                    } else if (dist > 0.4 && !hasFired) {
                                                        hasFired = true;
                                                        trackPulseAnim.restart();
                                                        ringPulseAnim.restart();
                                                        flashFadeAnim.restart();
                                                    }
                                                }

                                                SequentialAnimation {
                                                    id: trackPulseAnim
                                                    NumberAnimation { target: sliderDelegate; property: "trackPulse"; from: 0.0; to: 1.0; duration: 1000; easing.type: Easing.OutQuart }
                                                }
                                                SequentialAnimation {
                                                    id: ringPulseAnim
                                                    NumberAnimation { target: sliderDelegate; property: "ringPulse"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutExpo }
                                                }
                                                SequentialAnimation {
                                                    id: flashFadeAnim
                                                    NumberAnimation { target: sliderDelegate; property: "flashFade"; from: 1.0; to: 0.0; duration: 1500; easing.type: Easing.OutSine }
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    spacing: root.s(4)
                                                    Slider {
                                                        id: eqSlider
                                                        Layout.fillHeight: true
                                                        Layout.alignment: Qt.AlignHCenter
                                                        orientation: Qt.Vertical
                                                        from: -12; to: 12
                                                        stepSize: 1
                                                        hoverEnabled: true

                                                        Connections {
                                                            target: root
                                                            function onEqDataChanged() {
                                                                if (!eqSlider.pressed) {
                                                                    if (root.eqData && root.eqData["b" + modelData.idx] !== undefined) {
                                                                        var p = Number(root.eqData["b" + modelData.idx]);
                                                                        if (!isNaN(p)) eqSlider.value = p;
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        Behavior on value {
                                                            enabled: !eqSlider.pressed
                                                            NumberAnimation {
                                                                duration: 350
                                                                easing.type: Easing.OutQuart
                                                            }
                                                        }

                                                        onPressedChanged: {
                                                            if (!pressed) {
                                                                var temp = Object.assign({}, root.eqData);
                                                                temp["b" + modelData.idx] = Math.round(value);
                                                                temp.preset = "Custom";
                                                                temp.pending = true;
                                                                root.eqData = temp;

                                                                root.lastEqUpdate = Date.now();

                                                                root.execCmd(Caching.payloadDir + `/media/equalizer.sh set_band ${modelData.idx} ${Math.round(value)}`);
                                                            }
                                                        }

                                                        background: Rectangle {
                                                            id: trackBg
                                                            x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                            y: eqSlider.topPadding
                                                            implicitWidth: root.s(12)
                                                            implicitHeight: root.s(130)
                                                            width: root.s(12); height: eqSlider.availableHeight
                                                            radius: ThemeBackend.borderRadius

                                                            color: trackGlass.active ? "transparent" : Qt.rgba((ThemeBackend.surface0 ? ThemeBackend.surface0.r : 0.2), (ThemeBackend.surface0 ? ThemeBackend.surface0.g : 0.2), (ThemeBackend.surface0 ? ThemeBackend.surface0.b : 0.3), 0.7 * ThemeBackend.elementOpacity)

                                                            GlassFill {
                                                                id: trackGlass
                                                                anchors.fill: parent
                                                                radius: parent.radius
                                                                tintColor: ThemeBackend.surface0
                                                                tintAmount: 0.3
                                                            }

                                                            layer.enabled: true
                                                            layer.effect: MultiEffect {
                                                                id: trackEffect
                                                                shadowEnabled: true
                                                                shadowColor: "#000000"
                                                                shadowOpacity: 0.9
                                                                shadowBlur: 0.5
                                                                shadowVerticalOffset: 1
                                                            }

                                                            Rectangle {
                                                                z: -1
                                                                anchors.centerIn: parent
                                                                width: parent.width + root.s(17) + sliderDelegate.ringPulse * root.s(34)
                                                                height: parent.height + root.s(17) + sliderDelegate.ringPulse * root.s(51)
                                                                radius: parent.radius + root.s(8) + sliderDelegate.ringPulse * root.s(17)
                                                                color: "transparent"
                                                                border.color: root.eqAccentColor
                                                                border.width: root.s(2) + sliderDelegate.ringPulse * root.s(4)
                                                                opacity: sliderDelegate.ringPulse * 0.8 * (1.0 - root.eqLightningFade)

                                                                layer.enabled: true
                                                                layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                            }

                                                            Item {
                                                                width: parent.width
                                                                height: (1 - eqSlider.visualPosition) * parent.height
                                                                y: eqSlider.visualPosition * parent.height

                                                                layer.enabled: true
                                                                layer.effect: MultiEffect {
                                                                    maskEnabled: true
                                                                    maskSource: eqFillMask
                                                                }

                                                                Rectangle {
                                                                    id: eqFillMask
                                                                    anchors.fill: parent
                                                                    radius: ThemeBackend.borderRadius
                                                                    visible: false
                                                                    layer.enabled: true
                                                                }

                                                                GlassFill {
                                                                    id: eqFillGlass
                                                                    anchors.fill: parent
                                                                    radius: ThemeBackend.borderRadius
                                                                    forceClear: true
                                                                    tintColor: (root ? root.eqAccentColor : ThemeBackend.mauve)
                                                                    tintAmount: 0.6
                                                                    tintStrength: 1.0
                                                                    press: eqSlider.pressed ? 0.5 : (eqSlider.hovered ? 0.2 : 0)
                                                                    Behavior on press { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                                                }

                                                                Rectangle {
                                                                    anchors.fill: parent
                                                                    color: eqFillGlass.active ? "transparent" : (root ? root.eqAccentColor : ThemeBackend.mauve)

                                                                    Rectangle {
                                                                        anchors.fill: parent
                                                                        opacity: sliderDelegate.flashFade
                                                                        gradient: Gradient {
                                                                            orientation: Gradient.Vertical
                                                                            GradientStop { position: 0.0; color: Qt.lighter(root.eqAccentColor, 1.3) }
                                                                            GradientStop { position: 0.5; color: root.eqAccentColor }
                                                                            GradientStop { position: 1.0; color: "transparent" }
                                                                        }
                                                                    }

                                                                    Rectangle {
                                                                        width: parent.width
                                                                        height: root.s(70)
                                                                        y: (sliderDelegate.trackPulse * (parent.height + height)) - height
                                                                        opacity: Math.sin(sliderDelegate.trackPulse * Math.PI) * 2.0 * (1.0 - root.eqLightningFade)

                                                                        gradient: Gradient {
                                                                            orientation: Gradient.Vertical
                                                                            GradientStop { position: 0.0; color: "transparent" }
                                                                            GradientStop { position: 0.2; color: root.eqAccentColor }
                                                                            GradientStop { position: 0.5; color: ThemeBackend.text || "#ffffff" }
                                                                            GradientStop { position: 0.8; color: Qt.lighter(root.eqAccentColor, 1.2) }
                                                                            GradientStop { position: 1.0; color: "transparent" }
                                                                        }

                                                                        layer.enabled: true
                                                                        layer.effect: MultiEffect {
                                                                            shadowEnabled: true; shadowColor: root.eqAccentColor; shadowBlur: 1.0; shadowOpacity: 1.0
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        handle: Rectangle {
                                                            id: eqHandle
                                                            x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                            y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                                            implicitWidth: root.s(16)
                                                            implicitHeight: root.s(16)
                                                            width: root.s(16); height: root.s(16)
                                                            radius: root.s(8)

                                                            property color handleColor: ThemeBackend.text || "#cdd6f4"
                                                            property color handleHoverColor: Qt.lighter(root.eqAccentColor, 1.15)
                                                            property color handleDragColor: Qt.lighter(root.eqAccentColor, 1.30)

                                                            color: eqHandleGlass.active ? "transparent" : (eqSlider.pressed ? handleDragColor : (eqSlider.hovered ? handleHoverColor : handleColor))

                                                            GlassFill {
                                                                id: eqHandleGlass
                                                                anchors.fill: parent
                                                                radius: parent.radius
                                                                tintColor: parent.handleColor
                                                                tintAmount: 0.4
                                                                shadow: 1
                                                                press: eqSlider.pressed ? 1 : (eqSlider.hovered ? 0.3 : 0)
                                                                Behavior on press { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                                            }
                                                            Behavior on color { ColorAnimation { duration: 150 } }

                                                            property real targetScale: {
                                                                if (eqSlider.pressed) return 1.25;
                                                                if (eqSlider.hovered) return 1.08;
                                                                return 1.0;
                                                            }

                                                            Behavior on targetScale {
                                                                NumberAnimation {
                                                                    duration: 150
                                                                    easing.type: Easing.OutBack
                                                                }
                                                            }

                                                            property real popScale: 1.0
                                                            property real flashOpacity: 0.0

                                                            SequentialAnimation {
                                                                id: eqHandlePopAnim
                                                                NumberAnimation { target: eqHandle; property: "popScale"; to: 1.12; duration: 100; easing.type: Easing.OutQuad }
                                                                NumberAnimation { target: eqHandle; property: "popScale"; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
                                                            }

                                                            Connections {
                                                                target: eqSlider
                                                                function onMoved() {
                                                                    eqHandlePopAnim.restart();
                                                                }
                                                                function onPressedChanged() {
                                                                    if (!eqSlider.pressed) {
                                                                        eqHandle.flashOpacity = 0.35;
                                                                        eqHandleFlashAnim.restart();
                                                                    }
                                                                }
                                                            }

                                                            property var catColors: [
                                                                root.eqAccentColor,
                                                                ThemeBackend.pink || "#f5c2e7",
                                                                ThemeBackend.lavender || "#b4befe",
                                                                root.eqAccentColor,
                                                                ThemeBackend.blue || "#89b4fa"
                                                            ]

                                                            Rectangle {
                                                                anchors.centerIn: parent
                                                                width: parent.width + root.s(31) * sliderDelegate.hitPulse
                                                                height: width
                                                                radius: width / 2
                                                                color: (parent.catColors && parent.catColors.length > 0) ? (parent.catColors[(typeof index !== "undefined" ? index : 0) % parent.catColors.length] || root.eqAccentColor) : root.eqAccentColor
                                                                opacity: sliderDelegate.hitPulse * (1.0 - root.eqLightningFade)
                                                                layer.enabled: true
                                                                layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                            }

                                                            Rectangle {
                                                                anchors.fill: parent
                                                                radius: parent.radius
                                                                color: "#ffffff"
                                                                opacity: eqHandle.flashOpacity
                                                                PropertyAnimation on opacity { id: eqHandleFlashAnim; to: 0; duration: 300; easing.type: Easing.OutCubic }
                                                            }

                                                            scale: (targetScale * popScale) + (sliderDelegate.hitPulse * 0.4 * (1.0 - root.eqLightningFade))
                                                        }
                                                    }
                                                    Text {
                                                        text: modelData.lbl
                                                        color: ThemeBackend.overlay1 || "#7f849c"
                                                        font.family: ThemeBackend.fontFamily
                                                        font.pixelSize: root.s(9.5)
                                                        font.bold: true
                                                        Layout.alignment: Qt.AlignHCenter
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    ShaderEffect {
                                        id: lightningCanvas
                                        anchors.fill: parent
                                        opacity: 1.0 - root.eqLightningFade
                                        z: 0

                                        property real animTime: 0.0
                                        NumberAnimation on animTime {
                                            running: root.active
                                            loops: Animation.Infinite
                                            from: 0; to: 1000
                                            duration: 1000000
                                        }

                                        property vector2d itemSize: Qt.vector2d(width, height)
                                        property real time: animTime
                                        property real progress: root.eqLightningProgress
                                        property real fade: root.eqLightningFade
                                        property real scale: root.s(1.0)
                                        property color accentColor: root.eqAccentColor

                                        property vector4d bands0: Qt.vector4d(
                                            root.eqData.b1 !== undefined ? Number(root.eqData.b1) : 0,
                                            root.eqData.b2 !== undefined ? Number(root.eqData.b2) : 0,
                                            root.eqData.b3 !== undefined ? Number(root.eqData.b3) : 0,
                                            root.eqData.b4 !== undefined ? Number(root.eqData.b4) : 0
                                        )
                                        property vector4d bands1: Qt.vector4d(
                                            root.eqData.b5 !== undefined ? Number(root.eqData.b5) : 0,
                                            root.eqData.b6 !== undefined ? Number(root.eqData.b6) : 0,
                                            root.eqData.b7 !== undefined ? Number(root.eqData.b7) : 0,
                                            root.eqData.b8 !== undefined ? Number(root.eqData.b8) : 0
                                        )
                                        property vector4d bands2: Qt.vector4d(
                                            root.eqData.b9 !== undefined ? Number(root.eqData.b9) : 0,
                                            root.eqData.b10 !== undefined ? Number(root.eqData.b10) : 0,
                                            root.s(10),
                                            root.s(30)
                                        )

                                        fragmentShader: "file://" + Caching.assetsPath + "/shaders/vfx/eq_lightning.frag.qsb"
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(7)

                                    opacity: root.introPresets
                                    transform: Translate { y: root.s(18) * (1 - root.introPresets) }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: root.s(8)
                                        Repeater {
                                            model: ["Flat", "Bass", "Treble", "Vocal"]
                                            delegate: PresetButton { name: modelData }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: root.s(8)
                                        Repeater {
                                            model: ["Pop", "Rock", "Jazz", "Classic"]
                                            delegate: PresetButton { name: modelData }
                                        }
                                    }
                                }
                            }
=======
                        MusicEqView {
                            root: popupRoot
>>>>>>> upstream Ryoku 1.8.2 (fb5f2c2)
                        }

                        MusicAudioView {
                            id: audioView
                            root: popupRoot
                        }

                        MusicLyricsView {
                            root: popupRoot
                        }
                    }
                }
            }
        }
    }
}
