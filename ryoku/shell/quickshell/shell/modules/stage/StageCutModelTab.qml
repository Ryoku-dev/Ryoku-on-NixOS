pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons" as StageCfg

Column {
    id: root

    required property string mode

    width: parent ? parent.width : 0
    spacing: Tokens.s4

    readonly property var backend: StageCfg.StageBackend
    readonly property var cfg: StageCfg.Config
    readonly property string selectedId: root.cfg.cutModel(root.mode)
    readonly property var selectedModel: root.backend.modelById(root.selectedId)
    readonly property bool selectedInstalled: root.backend.cutModelInstalled(root.selectedId)

    function useNote(id) {
        if (id === "u2netp")
            return I18n.tr("Fast and compact for most wallpapers");
        if (id === "silueta")
            return I18n.tr("Lightweight for clean silhouettes");
        if (id === "birefnet-general-lite")
            return I18n.tr("Detailed general-purpose cut-outs");
        if (id === "birefnet-general")
            return I18n.tr("Highest-detail general cut-outs");
        if (id === "birefnet-portrait")
            return I18n.tr("Detailed portraits, people and hair");
        return I18n.tr("General wallpaper cut-outs");
    }

    Component.onCompleted: if (!root.backend.checked)
        root.backend.recheck()

    SettingCard {
        width: parent.width
        title: I18n.tr("CUT-OUT MODEL")
        kana: "切"
        summary: root.selectedModel
            ? I18n.tr(String(root.selectedModel.label || root.selectedModel.id)) : ""
        collapsible: false

        Empty {
            visible: !root.backend.checked && (root.backend.models || []).length === 0
            width: parent.width
            caption: I18n.tr("Checking the cut-out model catalogue")
        }

        Repeater {
            model: root.backend.models || []

            delegate: SettingRow {
                id: modelRow

                required property var modelData
                required property int index
                readonly property bool selected: String(modelData.id) === root.selectedId
                readonly property bool installed: root.backend.cutModelInstalled(String(modelData.id))

                width: parent.width
                divider: index > 0
                label: I18n.tr(String(modelData.label || modelData.id))
                desc: root.useNote(String(modelData.id)) + "\n"
                    + I18n.tr("%1 · %2 · %3")
                        .arg(I18n.tr(String(modelData.size || I18n.tr("size unknown"))))
                        .arg(I18n.tr(String(modelData.licence || I18n.tr("licence unknown"))))
                        .arg(modelRow.installed ? I18n.tr("Installed") : I18n.tr("Not downloaded"))
                controlWidth: useButton.implicitWidth

                Btn {
                    id: useButton
                    text: modelRow.selected ? I18n.tr("Selected") : I18n.tr("Use")
                    compact: true
                    primary: modelRow.selected
                    armed: !modelRow.selected
                        && !root.backend.installing && !root.backend.removing
                    onAct: root.cfg.setCutModel(root.mode, String(modelRow.modelData.id))
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
                : I18n.tr("The first download also prepares the cut-out runtime")
            block: true

            Flow {
                width: parent.width
                spacing: Tokens.s2

                Btn {
                    visible: !root.selectedInstalled
                    text: root.backend.installingModel === root.selectedId
                        ? I18n.tr("Downloading…") : I18n.tr("Download")
                    compact: true
                    primary: true
                    armed: !root.backend.installing && !root.backend.removing
                    onAct: root.backend.install(root.selectedId)
                }

                Btn {
                    visible: root.backend.installing
                    text: I18n.tr("Cancel download")
                    compact: true
                    onAct: root.backend.cancelInstall()
                }

                Btn {
                    visible: root.selectedInstalled
                    text: root.backend.removingModel === root.selectedId
                        ? I18n.tr("Removing…") : I18n.tr("Remove")
                    compact: true
                    armed: !root.backend.installing && !root.backend.removing
                    onAct: root.backend.remove(root.selectedId)
                }

            }
        }

        SettingRow {
            visible: root.backend.installing
                || (root.backend.removing && root.backend.progress !== "")
            width: parent.width
            divider: true
            label: root.backend.installing
                ? I18n.tr("Preparing the cut model") : I18n.tr("Removing the cut model")
            desc: root.backend.progress !== ""
                ? I18n.tr(String(root.backend.progress)) : I18n.tr("Starting download")
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Refine edges")
            desc: I18n.tr("Cleaner hair and fine edges, slower")
            controlWidth: Tokens.s7 + Tokens.s2
            Sw {
                anchors.right: parent.right
                on: root.cfg.cutMatting(root.mode)
                onToggled: value => root.cfg.setCutMatting(root.mode, value)
            }
        }
    }
}
