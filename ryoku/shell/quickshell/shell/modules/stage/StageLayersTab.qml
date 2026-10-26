pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons" as StageCfg

Column {
    id: root

    required property string mode
    required property string wall
    property string pickedCut: ""
    property bool regionPicking: false
    property bool clearArmed: false
    signal pickRequested(string kind)

    width: parent ? parent.width : 0
    spacing: Tokens.s4

    readonly property var backend: StageCfg.StageBackend
    readonly property int layerCount: root.backend.layerCountFor(root.wall)

    function acceptPicked(kind, path) {
        if (kind === "picture") {
            root.pickedCut = root.pathFromUrl(path);
        } else if (kind === "png") {
            root.backend.addLayer(root.pathFromUrl(path), root.wall);
        }
    }

    function pct(value) {
        return Math.round(Number(value) * 100) + "%";
    }

    function pathFromUrl(url) {
        const text = String(url || "");
        return text.indexOf("file://") === 0 ? decodeURIComponent(text.slice(7)) : text;
    }
    function fileUrl(path) {
        const text = String(path || "");
        return text === "" || text.indexOf("file://") === 0 ? text : "file://" + text;
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
            label: I18n.tr("Cut from this wallpaper")
            desc: I18n.tr("Draw a box around something and it becomes its own layer")
            controlWidth: chooseArea.implicitWidth
            Btn {
                id: chooseArea
                text: I18n.tr("Choose area")
                compact: true
                armed: !root.backend.busy
                onAct: root.regionPicking = true
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Cut from another picture")
            desc: I18n.tr("Pick a picture and its subject is cut out")
            controlWidth: choosePicture.implicitWidth
            Btn {
                id: choosePicture
                text: I18n.tr("Choose picture")
                compact: true
                armed: !root.backend.busy
                onAct: root.pickRequested("picture")
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Add a PNG")
            desc: I18n.tr("Use a transparent cut-out you already have")
            controlWidth: addPng.implicitWidth
            Btn {
                id: addPng
                text: I18n.tr("Choose")
                compact: true
                armed: !root.backend.busy
                onAct: root.pickRequested("png")
            }
        }

        SettingRow {
            id: busyRow
            readonly property var job: root.backend.job
            readonly property bool ownLayer: !!busyRow.job && busyRow.job.kind === "layer"
                && busyRow.job.wall === root.wall
            visible: !!busyRow.job
            width: parent.width
            divider: true
            label: busyRow.job && busyRow.job.state === "stopping"
                ? I18n.tr("Stopping")
                : busyRow.ownLayer ? I18n.tr("Cutting a new layer") : I18n.tr("Busy with another job")
            desc: busyRow.ownLayer
                ? I18n.tr("From %1").arg(busyRow.job.region === true
                    ? I18n.tr("this wallpaper") : root.leaf(busyRow.job.picture))
                : I18n.tr("New cuts wait until it finishes or is stopped.")
            block: true

            Flow {
                width: parent.width
                spacing: Tokens.s2
                Btn {
                    visible: !!busyRow.job && busyRow.job.state !== "stopping"
                    text: I18n.tr("Cancel")
                    compact: true
                    onAct: root.backend.cancel()
                }
                Btn {
                    text: I18n.tr("Force stop")
                    compact: true
                    primary: !!busyRow.job && busyRow.job.state === "stopping"
                    onAct: root.backend.forceCancel()
                }
            }
        }

        SettingRow {
            id: layerFailure
            readonly property var failed: {
                const result = root.backend.lastFor(root.wall);
                return result && result.kind === "layer" && result.state === "failed" ? result : null;
            }
            visible: layerFailure.failed !== null && !root.backend.busy
            width: parent.width
            divider: true
            label: I18n.tr("Couldn't cut that layer")
            desc: layerFailure.failed
                ? root.backend.errorWords(layerFailure.failed)
                    + (layerFailure.failed.detail ? "\n" + String(layerFailure.failed.detail) : "")
                : ""
        }
    }

    StageRegionPicker {
        visible: root.regionPicking
        width: parent.width
        wallpaperUrl: root.fileUrl(root.wall)
        interactive: !root.backend.busy
        onCanceled: root.regionPicking = false
        onChosen: (nx, ny, nw, nh) => {
            root.backend.cutRegion(nx, ny, nw, nh, root.wall);
            root.regionPicking = false;
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

            Column {
                width: parent.width
                spacing: Tokens.s2

                Image {
                    width: parent.width
                    height: Tokens.s7 * 2
                    source: root.fileUrl(root.pickedCut)
                    asynchronous: true
                    cache: false
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width
                    sourceSize.height: height
                }

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
                        armed: !root.backend.busy
                        onAct: {
                            root.backend.cutLayer(root.pickedCut, root.wall);
                            root.pickedCut = "";
                        }
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
                    onToggled: value => root.backend.setLayer(layerCard.index, { enabled: value }, root.wall)
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
                    onChose: value => root.backend.setLayerFront(layerCard.index, value === "front", root.wall)
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
                    onModified: value => root.backend.setLayerDepth(layerCard.index, value, root.wall)
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
                    onAct: root.backend.removeLayer(layerCard.index, root.wall)
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
                        root.backend.clear(root.wall);
                        root.clearArmed = false;
                    }
                }
            }
        }
    }

}
