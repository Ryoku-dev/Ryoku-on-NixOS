pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import stage.modules.common as StageIsland
import "Singletons" as StageCfg

Column {
    id: root

    required property string mode
    property string pickedCut: ""
    property bool clearArmed: false

    width: parent ? parent.width : 0
    spacing: Tokens.s4

    readonly property var backend: StageCfg.StageBackend
    readonly property var provider: StageIsland.Config.widgetProvider
    readonly property string wall: root.provider && root.provider.wallpaperPath
        ? root.provider.wallpaperPath : root.backend.current
    readonly property int layerCount: root.backend.layerCountFor(root.wall)

    function pct(value) {
        return Math.round(Number(value) * 100) + "%";
    }

    function pathFromUrl(url) {
        const text = String(url || "");
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.slice(7)) : text;
    }

    function leaf(path) {
        const parts = root.pathFromUrl(path).split("/");
        return parts.length > 0 ? parts[parts.length - 1] : "";
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("ADD LAYERS")
        kana: "層"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Cut a layer from a picture")
            desc: I18n.tr("Choose a picture, then confirm the cut")
            controlWidth: chooseCut.implicitWidth
            Btn {
                id: chooseCut
                text: I18n.tr("Choose")
                compact: true
                onAct: cutDialog.open()
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Add a PNG")
            desc: I18n.tr("Use an existing transparent cut-out")
            controlWidth: addPng.implicitWidth
            Btn {
                id: addPng
                text: I18n.tr("Choose")
                compact: true
                onAct: pngDialog.open()
            }
        }
    }

    SettingCard {
        visible: root.pickedCut !== ""
        width: parent.width
        title: I18n.tr("READY TO CUT")
        kana: "切"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Cut this picture into a new layer?")
            desc: I18n.tr("Selected: %1").arg(root.leaf(root.pickedCut))
            block: true

            Flow {
                width: parent.width
                spacing: Tokens.s2
                Btn {
                    text: I18n.tr("Cancel")
                    compact: true
                    onAct: root.pickedCut = ""
                }
                Btn {
                    text: I18n.tr("Cut")
                    compact: true
                    primary: true
                    onAct: {
                        root.backend.cutLayer(root.pathFromUrl(root.pickedCut));
                        root.pickedCut = "";
                    }
                }
            }
        }
    }

    Empty {
        visible: root.layerCount === 0
        width: parent.width
        caption: I18n.tr("No cut-outs yet. Cut the wallpaper or add a PNG to build the layer stack.")
    }

    Repeater {
        model: root.layerCount

        delegate: SettingCard {
            id: layerCard

            required property int index
            readonly property string layerName: root.backend.layerLabel(root.wall, index)

            width: parent ? parent.width : 0
            title: I18n.tr(String(layerCard.layerName).toUpperCase())
            kana: index === 0 ? "主" : "層"
            collapsible: false

            SettingRow {
                width: parent.width
                label: I18n.tr("Shown")
                desc: I18n.tr("Draw this cut-out in the scene")
                controlWidth: Tokens.s7 + Tokens.s2
                Sw {
                    anchors.right: parent.right
                    on: root.backend.layerEnabled(root.wall, layerCard.index)
                    onToggled: value => root.backend.setLayer(layerCard.index, { enabled: value })
                }
            }

            SettingRow {
                width: parent.width
                divider: true
                label: I18n.tr("Plane")
                desc: I18n.tr("Place the cut-out behind or over the desktop")
                controlWidth: width * 0.5
                Seg {
                    width: parent.width
                    options: ["behind", "front"]
                    labels: ({
                        behind: I18n.tr("Behind"),
                        front: I18n.tr("In front")
                    })
                    current: root.backend.layerFront(root.wall, layerCard.index)
                        ? "front" : "behind"
                    onChose: value => root.backend.setLayerFront(layerCard.index, value === "front")
                }
            }

            SettingRow {
                visible: root.mode === "parallax"
                width: parent.width
                divider: true
                label: I18n.tr("Distance")
                desc: I18n.tr("How far this layer travels in Parallax")
                    + " · " + root.pct(root.backend.layerDepth(root.wall, layerCard.index))
                value: root.pct(root.backend.layerDepth(root.wall, layerCard.index))
                block: true
                Slid {
                    width: parent.width
                    from: 0
                    to: 1
                    value: root.backend.layerDepth(root.wall, layerCard.index)
                    onModified: value => root.backend.setLayerDepth(layerCard.index, value)
                }
            }

            SettingRow {
                visible: layerCard.index > 0
                width: parent.width
                divider: true
                label: I18n.tr("Remove layer")
                desc: I18n.tr("The subject is kept as the scene's anchor")
                controlWidth: removeButton.implicitWidth
                Btn {
                    id: removeButton
                    text: I18n.tr("Remove")
                    compact: true
                    onAct: root.backend.removeLayer(layerCard.index)
                }
            }
        }
    }

    SettingCard {
        visible: root.layerCount > 0
        width: parent.width
        title: I18n.tr("CUT-OUTS")
        kana: "消"
        collapsible: false

        SettingRow {
            width: parent.width
            label: root.clearArmed
                ? I18n.tr("Remove every cut-out?")
                : I18n.tr("Clear cut-outs")
            desc: root.clearArmed
                ? I18n.tr("The wallpaper stays; every generated and added layer is removed")
                : I18n.tr("Start this wallpaper's layer stack again")
            block: root.clearArmed
            controlWidth: clearButton.implicitWidth

            Btn {
                id: clearButton
                visible: !root.clearArmed
                text: I18n.tr("Clear")
                compact: true
                onAct: root.clearArmed = true
            }

            Flow {
                visible: root.clearArmed
                width: parent.width
                spacing: Tokens.s2
                Btn {
                    text: I18n.tr("Cancel")
                    compact: true
                    onAct: root.clearArmed = false
                }
                Btn {
                    text: I18n.tr("Clear cut-outs")
                    compact: true
                    primary: true
                    onAct: {
                        root.backend.clear();
                        root.clearArmed = false;
                    }
                }
            }
        }
    }

    FileDialogHost {
        id: cutDialog
        currentFolder: "file://" + Quickshell.env("HOME") + "/Pictures"
        title: I18n.tr("Cut a layer from a picture")
        nameFilters: [
            I18n.tr("Pictures (*.png *.jpg *.jpeg *.webp *.bmp)"),
            I18n.tr("All files (*)")
        ]
        onAccepted: root.pickedCut = String(cutDialog.selectedFile)
    }

    FileDialogHost {
        id: pngDialog
        currentFolder: "file://" + Quickshell.env("HOME") + "/Pictures"
        title: I18n.tr("Add a PNG layer")
        nameFilters: [
            I18n.tr("PNG images (*.png)"),
            I18n.tr("All files (*)")
        ]
        onAccepted: root.backend.addLayer(root.pathFromUrl(pngDialog.selectedFile))
    }
}
