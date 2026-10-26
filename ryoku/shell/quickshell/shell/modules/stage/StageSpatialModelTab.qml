pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons" as StageCfg

Column {
    id: root

    width: parent ? parent.width : 0
    spacing: Tokens.s4

    readonly property var backend: StageCfg.StageBackend
    readonly property var cfg: StageCfg.Config
    readonly property string selectedId: root.cfg.spatialModel
    readonly property var selectedModel: root.backend.spatialModelById(root.selectedId)
    readonly property var fallbackModels: [
        { id: "small", label: I18n.tr("Depth Anything V2 Small"), size: "99 MB", licence: "Apache-2.0", installed: false },
        { id: "base", label: I18n.tr("Depth Anything V2 Base"), size: "389 MB", licence: "CC-BY-NC-4.0", installed: false },
        { id: "large", label: I18n.tr("Depth Anything V2 Large"), size: "1.34 GB", licence: "CC-BY-NC-4.0", installed: false }
    ]
    readonly property var catalogue: (root.backend.spatialModels || []).length > 0
        ? root.backend.spatialModels : root.fallbackModels

    function installed(model) {
        if (model && model.installed === true)
            return true;
        return String(model && model.id || "") === root.backend.spatialInstalledModel
            && root.backend.spatialInstalled;
    }

    function licence(model) {
        const id = String(model && model.id || "");
        if (id === "base" || id === "large")
            return I18n.tr("%1, non-commercial licence").arg(
                I18n.tr(String(model.licence || "CC-BY-NC-4.0")));
        return I18n.tr(String(model && model.licence || I18n.tr("licence unknown")));
    }

    readonly property bool selectedInstalled: {
        const model = root.backend.spatialModelById(root.selectedId);
        return root.installed(model || { id: root.selectedId, installed: false });
    }


    SettingCard {
        width: parent.width
        title: I18n.tr("SPATIAL MODEL")
        kana: "深"
        summary: root.selectedModel
            ? I18n.tr(String(root.selectedModel.label || root.selectedModel.id)) : ""
        collapsible: false

        Repeater {
            model: root.catalogue

            delegate: SettingRow {
                id: modelRow

                required property var modelData
                required property int index
                readonly property bool selected: String(modelData.id) === root.selectedId
                readonly property bool onDisk: root.installed(modelData)

                width: parent.width
                divider: index > 0
                label: I18n.tr(String(modelData.label || modelData.id))
                desc: I18n.tr("%1 · %2 · %3")
                    .arg(I18n.tr(String(modelData.size || I18n.tr("size unknown"))))
                    .arg(root.licence(modelData))
                    .arg(modelRow.onDisk ? I18n.tr("Installed") : I18n.tr("Not downloaded"))
                controlWidth: useButton.implicitWidth

                Btn {
                    id: useButton
                    text: modelRow.selected ? I18n.tr("Selected") : I18n.tr("Use")
                    compact: true
                    primary: modelRow.selected
                    armed: !modelRow.selected
                        && !root.backend.spatialInstalling && !root.backend.spatialRemoving
                    onAct: {
                        root.cfg.setSpatialModel(String(modelRow.modelData.id));
                        root.backend.recheckSpatial();
                    }
                }
            }
        }
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("MODEL ACTIONS")
        kana: "取"
        collapsible: false

        SettingRow {
            width: parent.width
            label: root.selectedInstalled
                ? I18n.tr("Model ready") : I18n.tr("Download selected model")
            desc: root.selectedInstalled
                ? I18n.tr("The selected model is available on this computer")
                : I18n.tr("Download the model once to build this wallpaper's depth map")
            block: true

            Flow {
                width: parent.width
                spacing: Tokens.s2

                Btn {
                    visible: !root.selectedInstalled
                    text: root.backend.spatialInstalling
                        ? I18n.tr("Downloading…") : I18n.tr("Download")
                    compact: true
                    primary: true
                    armed: !root.backend.spatialInstalling && !root.backend.spatialRemoving
                    onAct: root.backend.installSpatialModel(root.selectedId)
                }

                Btn {
                    visible: root.backend.spatialInstalling
                    text: I18n.tr("Cancel download")
                    compact: true
                    onAct: root.backend.cancelSpatialInstall()
                }

                Btn {
                    visible: root.selectedInstalled
                    text: root.backend.spatialRemoving
                        ? I18n.tr("Removing…") : I18n.tr("Remove")
                    compact: true
                    armed: !root.backend.spatialInstalling && !root.backend.spatialRemoving
                    onAct: root.backend.removeSpatialModel(root.selectedId)
                }

            }
        }

        SettingRow {
            visible: root.backend.spatialInstalling
                || ((root.backend.spatialChecking || root.backend.spatialRemoving)
                    && root.backend.spatialProgress !== "")
            width: parent.width
            divider: true
            label: root.backend.spatialRemoving
                ? I18n.tr("Removing the spatial model")
                : root.backend.spatialInstalling
                    ? I18n.tr("Preparing the spatial model")
                    : I18n.tr("Checking the spatial model")
            desc: root.backend.spatialProgress !== ""
                ? I18n.tr(String(root.backend.spatialProgress)) : I18n.tr("Starting download")
        }
    }
}
