pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import stage.modules.common as StageIsland
import "Singletons" as StageCfg

Item {
    id: page

    property string tab: ""

    readonly property var backend: StageCfg.StageBackend
    readonly property var cfg: StageCfg.Config
    readonly property var provider: StageIsland.Config.widgetProvider
    readonly property string wall: page.provider && page.provider.wallpaperPath
        ? page.provider.wallpaperPath : page.backend.current
    readonly property string mode: page.backend.effectFor(page.wall)
    readonly property bool video: page.isVideo(page.wall)
    readonly property int layerCount: page.backend.layerCountFor(page.wall)
    readonly property string stateDir: Quickshell.env("XDG_STATE_HOME")
        || (Quickshell.env("HOME") + "/.local/state")
    readonly property string previewPath: page.video
        ? page.stateDir + "/ryoku-live-frame.png" : page.wall

    function isVideo(path) {
        return /\.(mp4|webm|mkv|mov)$/i.test(String(path || ""));
    }

    function fileUrl(path) {
        const text = String(path || "");
        return text === "" || text.indexOf("file://") === 0 ? text : "file://" + text;
    }

    function modeName(value) {
        if (value === "depth")
            return I18n.tr("Depth");
        if (value === "parallax")
            return I18n.tr("Parallax");
        if (value === "spatial")
            return I18n.tr("Spatial");
        return I18n.tr("Plain");
    }

    function firstTabForMode(value) {
        if (value === "depth")
            return "look";
        if (value === "parallax")
            return "motion";
        if (value === "spatial")
            return "camera";
        return "";
    }

    function tabsForMode(value) {
        if (value === "depth")
            return ["look", "layers", "front", "model"];
        if (value === "parallax")
            return ["motion", "look", "layers", "front", "model"];
        if (value === "spatial")
            return ["camera", "model"];
        return [];
    }

    function resetTab() {
        page.tab = page.firstTabForMode(page.mode);
    }

    function statusLine() {
        if (page.video)
            return I18n.tr("Not available for video wallpapers");
        if (page.backend.busy) {
            if (page.mode === "spatial" || page.backend.stage === "depth")
                return I18n.tr("Building the depth map");
            return I18n.tr("Cutting the subject %1%").arg(page.backend.percent);
        }
        if ((page.mode === "depth" || page.mode === "parallax")
                && !page.backend.cutModelInstalled(page.cfg.cutModel(page.mode)))
            return I18n.tr("Pick a model in the Model tab");
        if (page.mode === "spatial" && !page.backend.spatialInstalled)
            return I18n.tr("Pick a model in the Model tab");
        return I18n.tr("Ready");
    }

    onModeChanged: page.resetTab()
    Component.onCompleted: page.resetTab()

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + Tokens.s4
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        QQC.ScrollBar.vertical: ScrollRail {
            policy: QQC.ScrollBar.AsNeeded
        }
        WheelScroll {}

        Column {
            id: content
            width: scroll.width
            spacing: Tokens.s4

            StageDepthHero {
                width: parent.width
                wallpaperUrl: page.fileUrl(page.previewPath)
                subjectUrl: (page.mode === "depth" || page.mode === "parallax")
                        && page.layerCount > 0
                    ? page.backend.layerUrlFor(page.wall, 0) : ""
                mode: page.modeName(page.mode)
                state: page.statusLine()
                busy: page.backend.busy
            }

            StageModePicker {
                width: parent.width
                mode: page.mode
                interactive: !page.video
                onChose: value => {
                    if (!page.video)
                        page.backend.setEffect(value);
                }
            }

            Chips {
                visible: page.mode !== "off"
                width: parent.width
                options: page.tabsForMode(page.mode)
                labels: ({
                    motion: I18n.tr("Motion"),
                    look: I18n.tr("Look"),
                    layers: I18n.tr("Layers"),
                    front: I18n.tr("Front"),
                    camera: I18n.tr("Camera"),
                    model: I18n.tr("Model")
                })
                current: page.tab
                onChose: value => page.tab = value
            }

            SettingCard {
                visible: page.mode === "off"
                width: parent.width
                title: I18n.tr("PLAIN WALLPAPER")
                kana: "平"
                collapsible: false

                SettingRow {
                    width: parent.width
                    block: true

                    Text {
                        width: parent.width
                        text: I18n.tr("Everything draws flat. Pick Depth, Parallax or Spatial to give this wallpaper depth.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StageMotionTab {
                visible: page.mode === "parallax" && page.tab === "motion"
                width: parent.width
                mode: page.mode
            }

            StageLookTab {
                visible: (page.mode === "depth" || page.mode === "parallax")
                    && page.tab === "look"
                width: parent.width
                mode: page.mode
            }

            StageLayersTab {
                visible: (page.mode === "depth" || page.mode === "parallax")
                    && page.tab === "layers"
                width: parent.width
                mode: page.mode
            }

            StageFrontTab {
                visible: (page.mode === "depth" || page.mode === "parallax")
                    && page.tab === "front"
                width: parent.width
                mode: page.mode
            }

            StageCameraTab {
                visible: page.mode === "spatial" && page.tab === "camera"
                width: parent.width
                mode: page.mode
            }

            StageCutModelTab {
                visible: (page.mode === "depth" || page.mode === "parallax")
                    && page.tab === "model"
                width: parent.width
                mode: page.mode
            }

            StageSpatialModelTab {
                visible: page.mode === "spatial" && page.tab === "model"
                width: parent.width
            }
        }
    }
}
