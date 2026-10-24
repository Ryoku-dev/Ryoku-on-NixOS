pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "../barstudio/StoreDesignGalleryModel.js" as GalleryModel

Item {
    id: gallery

    required property string category
    required property string wornId
    required property var shippedDesigns
    property var catalogueDesigns: []
    readonly property string cardObjectPrefix: gallery.category === "barstyles"
        ? "bar-style-" : "store-design-" + gallery.category + "-"
    readonly property string updateObjectPrefix: gallery.category === "barstyles"
        ? "bar-style-update-" : "store-design-update-" + gallery.category + "-"
    property string updatingId: ""
    property string extraActionText: ""
    readonly property var designs: gallery.cardModel()

    signal wear(string designId)
    signal extraAction()

    // Bundled styles stay installed even if a stale Store catalogue describes
    // them as downloadable or unavailable. This includes NixOS-owned Karuma.
    function cardModel() {
        return GalleryModel.galleryCards(gallery.category, gallery.shippedDesigns, gallery.catalogueDesigns);
    }

    function browse() {
        Quickshell.execDetached(["ryostore", "open", gallery.category]);
    }

    function updateDesign(id) {
        if (!id || gallery.updatingId !== "")
            return;
        gallery.updatingId = id;
        updateProcess.command = ["ryostore", "install", gallery.category, id];
        updateProcess.running = true;
    }

    function refresh() {
        catalogueProcess.running = false;
        catalogueProcess.running = true;
    }

    Process {
        id: catalogueProcess
        command: ["ryostore", "catalog", "--category", gallery.category]
        running: gallery.category !== ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const catalog = JSON.parse(this.text || "{}");
                    gallery.catalogueDesigns = (catalog.items || [])
                        .filter(item => item.category === gallery.category
                            && !(item.unavailable === true && item.installed !== true))
                        .map(item => ({
                            id: item.id,
                            name: item.name || item.id,
                            desc: item.summary || item.description || "",
                            installed: item.installed === true,
                            version: item.version || "",
                            installedVersion: item.installedVersion || "",
                            updateAvailable: item.updateAvailable === true,
                            unavailable: item.unavailable === true,
                            unavailableEdition: item.unavailableEdition === true,
                            unavailableReason: item.unavailableReason || "",
                            requiredWindowManager: item.requiredWindowManager || "",
                            downloadPaused: item.downloadPaused === true,
                            resourceTier: (item.metadata && item.metadata.resourceTier) || "",
                            downloadPauseReason: item.downloadPauseReason || ""
                        }));
                } catch (e) {
                    gallery.catalogueDesigns = [];
                }
            }
        }
    }

    Process {
        id: updateProcess
        onExited: {
            gallery.updatingId = "";
            gallery.refresh();
        }
    }

    implicitHeight: galleryBody.height + Tokens.s3 + Tokens.s4
    height: implicitHeight

    Column {
        id: galleryBody
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: Tokens.s4
            rightMargin: Tokens.s4
            topMargin: Tokens.s3
        }
        spacing: Tokens.s3

        Flow {
            id: cardFlow
            width: parent.width
            spacing: Tokens.s2
            readonly property int perRow: Math.max(2, Math.floor((width + Tokens.s2) / 210))
            readonly property bool hasResourceWarnings: gallery.designs.some(
                design => design.resourceTier === "heavy")
            readonly property int tileH: hasResourceWarnings ? 88 : 64
            readonly property int rowCount: Math.max(1, Math.ceil(cardRepeater.count / perRow))
            height: rowCount * tileH + (rowCount - 1) * spacing

            Repeater {
                id: cardRepeater
                model: gallery.designs

                delegate: Rectangle {
                    id: designCard

                    required property var modelData
                    readonly property bool wearable: designCard.modelData.installed && !designCard.modelData.unavailable
                    readonly property bool worn: designCard.wearable && gallery.wornId === designCard.modelData.id
                    readonly property bool updatable: designCard.modelData.updateAvailable === true
                        && designCard.modelData.version.length > 0
                        && !designCard.modelData.unavailable && !designCard.modelData.downloadPaused
                    readonly property bool heavy: designCard.modelData.resourceTier === "heavy"
                    readonly property string subText: {
                        if (designCard.updatable) {
                            const current = designCard.modelData.installedVersion.length > 0
                                ? designCard.modelData.installedVersion : designCard.modelData.version;
                            return I18n.tr("%1 → %2").arg(current).arg(designCard.modelData.version);
                        }
                        if (designCard.wearable)
                            return I18n.tr(designCard.modelData.desc);
                        if (designCard.modelData.unavailable) {
                            const wm = ("" + designCard.modelData.requiredWindowManager).toUpperCase();
                            const tag = designCard.modelData.unavailableEdition ? I18n.tr("Not on this system")
                                : wm.length > 0 ? I18n.tr("%1 only").arg(wm) : I18n.tr("Unavailable");
                            return designCard.modelData.unavailableReason.length > 0
                                ? tag + " · " + I18n.tr(designCard.modelData.unavailableReason) : tag;
                        }
                        if (designCard.modelData.downloadPaused)
                            return designCard.modelData.downloadPauseReason.length > 0
                                ? I18n.tr("Under construction") + " · " + I18n.tr(designCard.modelData.downloadPauseReason)
                                : I18n.tr("Under construction");
                        return I18n.tr("Available · install from RyoStore");
                    }

                    width: Math.floor((cardFlow.width - (cardFlow.perRow - 1) * Tokens.s2) / cardFlow.perRow)
                    height: cardFlow.tileH
                    radius: Tokens.radius
                    opacity: designCard.wearable ? 1.0 : 0.55
                    color: designCard.worn ? Tokens.bone : (cardMouse.containsMouse ? Tokens.tint5 : "transparent")
                    border.width: Tokens.border
                    border.color: designCard.worn ? Tokens.bone : Tokens.line
                    objectName: gallery.cardObjectPrefix + designCard.modelData.id

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: designCard.wearable ? gallery.wear(designCard.modelData.id) : gallery.browse()
                    }

                    Column {
                        anchors {
                            left: parent.left
                            right: updateButton.visible ? updateButton.left : parent.right
                            margins: Tokens.s3
                            rightMargin: updateButton.visible ? Tokens.s2 : Tokens.s3
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 3

                        Text {
                            text: I18n.tr(designCard.modelData.name).toUpperCase()
                            color: designCard.worn ? Tokens.inkOnBone : Tokens.inkDim
                            font.family: Tokens.ui
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            font.letterSpacing: Tokens.trackLabel
                        }
                        Text {
                            width: parent.width
                            text: designCard.subText
                            color: designCard.worn ? Tokens.inkOnBoneDim : Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fTiny
                            elide: Text.ElideRight
                        }
                        Row {
                            width: parent.width
                            spacing: Tokens.s2
                            visible: designCard.heavy

                            Text {
                                text: "▲"
                                color: Tokens.alert
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fMicro
                            }
                            Text {
                                width: Math.max(0, parent.width - x)
                                text: I18n.tr("May need more CPU, GPU and memory.")
                                color: designCard.worn ? Tokens.inkOnBoneDim : Tokens.inkFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fMicro
                                font.weight: Font.Medium
                                font.letterSpacing: Tokens.trackMark
                                font.capitalization: Font.AllUppercase
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Btn {
                        id: updateButton
                        anchors {
                            right: parent.right
                            rightMargin: Tokens.s3
                            verticalCenter: parent.verticalCenter
                        }
                        visible: designCard.updatable
                        compact: true
                        armed: gallery.updatingId === ""
                        text: gallery.updatingId === designCard.modelData.id
                            ? I18n.tr("UPDATING") : I18n.tr("UPDATE")
                        objectName: gallery.updateObjectPrefix + designCard.modelData.id
                        onAct: gallery.updateDesign(designCard.modelData.id)
                    }
                }
            }
        }

        Row {
            spacing: Tokens.s2

            Btn {
                text: I18n.tr("BROWSE RYOSTORE")
                onAct: gallery.browse()
            }
            Btn {
                visible: gallery.extraActionText !== ""
                text: gallery.extraActionText
                onAct: gallery.extraAction()
            }
        }
    }
}
