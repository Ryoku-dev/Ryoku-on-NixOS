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
    property string pickKind: ""

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

    function openPicker(kind) {
        page.pickKind = kind;
        filePicker.title = kind === "png"
            ? I18n.tr("Add a PNG layer") : I18n.tr("Cut a layer from another picture");
        filePicker.fileFilters = kind === "png"
            ? ["*.png"] : ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"];
        filePicker.open();
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
                statusText: page.video
                    ? I18n.tr("Not available for video wallpapers") : sceneCard.headline
                busy: page.backend.job !== null
            }

            StageModePicker {
                width: parent.width
                mode: page.mode
                interactive: !page.video
                onChose: value => {
                    if (!page.video)
                        page.backend.setEffect(value, page.wall);
                }
            }
            StageSceneCard {
                id: sceneCard
                visible: page.mode !== "off" && !page.video
                width: parent.width
                wall: page.wall
                mode: page.mode
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
                id: layersTab
                visible: (page.mode === "depth" || page.mode === "parallax")
                    && page.tab === "layers"
                width: parent.width
                mode: page.mode
                wall: page.wall
                onPickRequested: kind => page.openPicker(kind)
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

    PickFile {
        id: filePicker
        title: I18n.tr("Choose a picture")
        onPicked: path => {
            layersTab.acceptPicked(page.pickKind, path);
            filePicker.active = false;
            page.pickKind = "";
        }
        onCanceled: {
            filePicker.active = false;
            page.pickKind = "";
        }
    }
}
