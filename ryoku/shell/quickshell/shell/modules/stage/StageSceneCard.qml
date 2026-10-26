pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons" as StageCfg

SettingCard {
    id: card

    required property string wall
    required property string mode

    width: parent ? parent.width : 0
    title: I18n.tr("THIS WALLPAPER")
    kana: "作"
    collapsible: false

    readonly property var backend: StageCfg.StageBackend
    readonly property var steps: card.backend.stepsFor(card.wall)
    readonly property var wallJob: card.backend.jobFor(card.wall)
    readonly property var otherJob: card.backend.job && !card.wallJob ? card.backend.job : null
    // Ignore layer and other-mode results so failures stay with their owning editor.
    readonly property var wallLast: {
        const result = card.backend.lastFor(card.wall);
        return result && result.kind === "scene" && result.mode === card.mode ? result : null;
    }
    readonly property var sceneJob: card.wallJob && card.wallJob.kind === "scene" ? card.wallJob : null
    readonly property string headline: card.headlineFor()
    readonly property string statusLine: card.lineFor()
    readonly property var neededModel: card.neededModelForWork()
    readonly property bool downloading: card.neededModel
        && (card.neededModel.kind === "cut"
            ? card.backend.installing : card.backend.spatialInstalling)
    property double now: Date.now()

    function modeLabel(value) {
        if (value === "depth") return I18n.tr("Depth");
        if (value === "parallax") return I18n.tr("Parallax");
        if (value === "spatial") return I18n.tr("Spatial");
        return I18n.tr("Plain");
    }

    function stepLabel(value) {
        return card.backend.stepLabel(value);
    }

    function modelForStep(step, id) {
        return card.backend.modelLabel(step, id);
    }

    function elapsed(started) {
        const seconds = Math.max(0, Math.floor((card.now - Number(started || card.now)) / 1000));
        const minutes = Math.floor(seconds / 60);
        const rest = seconds % 60;
        return minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }

    function stepPosition(job, step) {
        const sequence = job && Array.isArray(job.steps) ? job.steps : [];
        return sequence.indexOf(step);
    }

    function stepDescription(data) {
        const step = String(data && data.step || "");
        if (card.sceneJob) {
            const position = card.stepPosition(card.sceneJob, step);
            const current = Number(card.sceneJob.index || 0);
            if (position >= 0 && position < current) return I18n.tr("Done");
            if (position === current)
                return I18n.tr("Running · %1").arg(card.elapsed(card.sceneJob.stepStarted));
            if (position > current) return I18n.tr("Waiting");
        }

        const state = String(data && data.state || "");
        const wanted = card.modelForStep(step, String(data && data.want || ""));
        if (state === "outdated") {
            const madeWith = card.modelForStep(step, String(data && data.model || ""));
            return I18n.tr("Made with %1, you picked %2")
                .arg(madeWith || I18n.tr("another model"))
                .arg(wanted || I18n.tr("another model"));
        }
        var words = "";
        if (state === "ready") words = I18n.tr("Ready");
        else if (state === "missing") words = I18n.tr("Not done yet");
        else if (state === "stale") words = I18n.tr("Out of date: the wallpaper changed");
        if (wanted && words) return wanted + " · " + words;
        return words || wanted;
    }

    function hasState(value) {
        for (var i = 0; i < card.steps.length; i++)
            if (card.steps[i] && card.steps[i].state === value) return true;
        return false;
    }

    function nothingGenerated() {
        if (card.steps.length === 0) return true;
        for (var i = 0; i < card.steps.length; i++)
            if (!card.steps[i] || card.steps[i].state !== "missing") return false;
        return true;
    }

    function jobStepLine(job) {
        const count = job && Array.isArray(job.steps) ? job.steps.length : 0;
        const index = Math.max(0, Number(job && job.index || 0));
        return I18n.tr("Step %1 of %2: %3")
            .arg(Math.min(count, index + 1)).arg(count)
            .arg(card.stepLabel(job && job.step));
    }

    function leaf(path) {
        const parts = decodeURIComponent(String(path || "").replace(/^file:\/\//, "")).split("/");
        return parts.length ? parts[parts.length - 1] : "";
    }

    function headlineFor() {
        const job = card.backend.job;
        if (job) {
            if (!card.wallJob) return I18n.tr("Busy with another wallpaper");
            if (job.state === "stopping") return I18n.tr("Stopping");
            if (job.kind === "layer") return I18n.tr("Cutting a new layer");
            return I18n.tr("Generating %1").arg(card.modeLabel(job.mode || card.mode));
        }
        if (card.mode === "off") return I18n.tr("Ready");
        if (card.wallLast && card.wallLast.state === "failed") return I18n.tr("Couldn't finish");
        if (card.wallLast && card.wallLast.state === "cancelled") return I18n.tr("Stopped");
        if (card.nothingGenerated()) return I18n.tr("Not generated yet");
        if (card.backend.needsWorkFor(card.wall)) return I18n.tr("Needs an update");
        return I18n.tr("Ready");
    }

    function errorWords(result) {
        return card.backend.errorWords(result);
    }

    function lineFor() {
        const job = card.backend.job;
        if (job) {
            if (!card.wallJob) return card.jobStepLine(job);
            if (job.state === "stopping")
                return I18n.tr("Waiting for the model to stop. Force stop ends it right away.");
            if (job.kind === "layer") {
                const source = job.region === true ? I18n.tr("this wallpaper") : card.leaf(job.picture);
                return I18n.tr("From %1").arg(source);
            }
            return card.jobStepLine(job);
        }
        if (card.wallLast && card.wallLast.state === "failed") {
            const detail = String(card.wallLast.detail || "");
            return card.errorWords(card.wallLast) + (detail ? "\n" + detail : "");
        }
        if (card.wallLast && card.wallLast.state === "cancelled")
            return I18n.tr("Nothing changed. Any earlier result is still in place.");
        if (card.nothingGenerated())
            return I18n.tr("Nothing runs until you press Generate. It takes a few seconds to a few minutes, depending on the model.");
        if (card.backend.needsWorkFor(card.wall))
            return I18n.tr("Some steps are missing or were made with other settings.");
        return I18n.tr("Everything this mode needs is in place.");
    }

    function spatialInstalled(id) {
        const model = card.backend.spatialModelById(id);
        if (model && model.installed === true) return true;
        return card.backend.spatialInstalled
            && String(card.backend.spatialInstalledModel) === String(id);
    }

    // Redo uses the current model selection; fill is the only model-free step.
    function wantInstalled(step) {
        const id = String(step && step.want || "");
        if (!step || step.step === "fill" || !id) return true;
        return step.step === "depth" ? card.spatialInstalled(id) : card.backend.cutModelInstalled(id);
    }

    function neededModelForWork() {
        for (var i = 0; i < card.steps.length; i++) {
            const step = card.steps[i] || {};
            if (step.state === "ready") continue;
            const id = String(step.want || "");
            if (!id || step.step === "fill") continue;
            const model = step.step === "depth"
                ? card.backend.spatialModelById(id) : card.backend.modelById(id);
            const installed = step.step === "depth"
                ? card.spatialInstalled(id) : card.backend.cutModelInstalled(id);
            if (!installed) return {
                kind: step.step === "depth" ? "spatial" : "cut",
                id: id,
                label: I18n.tr(String(model && (model.label || model.id) || id)),
                size: I18n.tr(String(model && model.size || I18n.tr("size unknown")))
            };
        }
        return null;
    }

    function idleActionText() {
        if (card.wallLast && card.wallLast.state === "failed") return I18n.tr("Try again");
        if (card.nothingGenerated()) return I18n.tr("Generate");
        if (!card.backend.needsWorkFor(card.wall)) return I18n.tr("Redo all");
        return card.hasState("missing") ? I18n.tr("Generate") : I18n.tr("Update");
    }

    function runIdleAction() {
        if (card.wallLast && card.wallLast.state === "failed" && !card.backend.needsWorkFor(card.wall))
            card.backend.redo(String(card.wallLast.step || ""), card.wall);
        else if (card.wallLast && card.wallLast.state === "failed")
            card.backend.generate(card.wall);
        else if (!card.backend.needsWorkFor(card.wall))
            card.backend.redo("", card.wall);
        else
            card.backend.generate(card.wall);
    }

    function startDownload() {
        if (!card.neededModel) return;
        if (card.neededModel.kind === "spatial")
            card.backend.installSpatialModel(card.neededModel.id);
        else
            card.backend.install(card.neededModel.id);
    }

    function cancelDownload() {
        if (!card.neededModel) return;
        if (card.neededModel.kind === "spatial") card.backend.cancelSpatialInstall();
        else card.backend.cancelInstall();
    }

    Timer {
        interval: 1000
        repeat: true
        running: card.visible && card.backend.job !== null
        onTriggered: card.now = Date.now()
    }
    // Keep actions in a fixed block; toggling SettingRow.block leaves stale control geometry.
    SettingRow {
        width: parent.width
        label: card.headline
        desc: card.otherJob
            ? card.statusLine + "\n" + I18n.tr("Another wallpaper's job is running. Stop it here or wait for it.")
            : card.statusLine
        block: true

        Flow {
            width: parent.width
            spacing: Tokens.s2

            // Jobs are global, so every wallpaper card must be able to stop the active one.
            Btn {
                visible: !!card.backend.job && card.backend.job.state !== "stopping"
                text: I18n.tr("Cancel")
                compact: true
                onAct: card.backend.cancel()
            }
            Btn {
                visible: !!card.backend.job
                text: I18n.tr("Force stop")
                compact: true
                primary: !!card.backend.job && card.backend.job.state === "stopping"
                onAct: card.backend.forceCancel()
            }
            Btn {
                visible: !card.backend.job && card.downloading
                text: I18n.tr("Cancel download")
                compact: true
                primary: true
                onAct: card.cancelDownload()
            }
            Btn {
                visible: !card.backend.job && !card.downloading && !!card.neededModel
                text: card.neededModel
                    ? I18n.tr("Download %1 (%2)").arg(card.neededModel.label).arg(card.neededModel.size) : ""
                compact: true
                primary: true
                armed: !card.backend.removing && !card.backend.spatialRemoving
                onAct: card.startDownload()
            }
            Btn {
                visible: !card.backend.job && !card.neededModel && !card.downloading
                text: card.idleActionText()
                compact: !card.nothingGenerated() && !card.backend.needsWorkFor(card.wall)
                    && !(card.wallLast && card.wallLast.state === "failed")
                primary: card.nothingGenerated() || card.backend.needsWorkFor(card.wall)
                    || (card.wallLast && card.wallLast.state === "failed")
                armed: !card.backend.installing && !card.backend.removing
                    && !card.backend.spatialInstalling && !card.backend.spatialRemoving
                onAct: card.runIdleAction()
            }
        }
    }

    Item {
        visible: !!card.wallJob
        width: parent.width
        height: visible ? Tokens.s3 : 0

        Rectangle {
            id: progressTrack
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: Tokens.s4
                rightMargin: Tokens.s4
            }
            height: 3
            radius: height / 2
            color: Tokens.lineSoft
            clip: true
            property real phase: 0

            Rectangle {
                width: Math.max(24, parent.width * 0.28)
                height: parent.height
                radius: height / 2
                color: Tokens.bone
                x: Tokens.reduceMotion ? (parent.width - width) / 2
                    : progressTrack.phase * (parent.width + width) - width
            }
            NumberAnimation on phase {
                from: 0
                to: 1
                duration: 1100
                loops: Animation.Infinite
                running: card.visible && progressTrack.visible && !Tokens.reduceMotion
            }
        }
    }

    Repeater {
        model: card.steps

        delegate: SettingRow {
            id: stepRow

            required property var modelData
            required property int index
            readonly property string stepName: String(modelData && modelData.step || "")
            readonly property bool canRedo: !card.backend.job
                && String(modelData && modelData.state || "") !== "missing"

            width: parent ? parent.width : 0
            divider: true
            label: card.stepLabel(stepRow.stepName)
            desc: card.stepDescription(stepRow.modelData)
            controlWidth: stepRow.canRedo ? redoButton.implicitWidth : 0

            Btn {
                id: redoButton
                visible: stepRow.canRedo
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Redo")
                compact: true
                armed: card.wantInstalled(stepRow.modelData)
                    && !card.backend.installing && !card.backend.removing
                    && !card.backend.spatialInstalling && !card.backend.spatialRemoving
                onAct: card.backend.redo(stepRow.stepName, card.wall)
            }
        }
    }

    SettingRow {
        visible: card.downloading
        width: parent.width
        divider: true
        label: card.neededModel && card.neededModel.kind === "spatial"
            ? I18n.tr("Preparing the spatial model") : I18n.tr("Preparing the cut model")
        desc: String(card.neededModel && card.neededModel.kind === "spatial"
            ? card.backend.spatialProgress : card.backend.progress) || I18n.tr("Starting download")
    }
}
