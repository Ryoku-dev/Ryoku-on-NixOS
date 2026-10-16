import QtQuick
import QtQuick.Layouts
import Ryoku.Ui as RyokuUi
import stage.services
import stage.modules.common
import stage.modules.common.widgets
ContentPage {
    id: root
    forceWidth: false

    property string configEntryName: "photo"
    property string widgetIdName: "photo"
    property string titleText: Translation.tr("Photo Widget Options")

    readonly property var configEntry: Config.options.background.widgets[root.configEntryName]
    readonly property string currentImagePath: String(root.configEntry?.imagePath ?? "")

    function setImagePath(path) {
        if (root.configEntry)
            root.configEntry.imagePath = path;
    }

    RyokuUi.FileDialogHost {
        id: imageDialog
        title: Translation.tr("Choose an image")
        nameFilters: [Translation.tr("Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)"), Translation.tr("All files (*)")]
        onAccepted: root.setImagePath(String(imageDialog.selectedFile))
    }

    signal goBack


    RowLayout {
        spacing: 12

        RippleButton {
            implicitWidth: implicitHeight
            implicitHeight: 40
            topLeftRadius: Appearance.rounding.full
            topRightRadius: Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive

            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }

            onClicked: root.goBack()
        }

        StyledText {
            text: root.titleText
            font.pixelSize: Appearance.font.pixelSize.large
            font.family: Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Photo Settings")
        icon: "image"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive(root.widgetIdName)

            PagePlaceholder {
                anchors.fill: parent
                icon: "image"
                shape: MaterialShape.Shape.Circle
                title: Translation.tr("Photo widget disabled")
                description: Translation.tr("Enable the desktop photo widget in Desktop Widgets settings to use this page.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive(root.widgetIdName)

            RippleButtonWithIcon {
                Layout.fillWidth: true
                materialIcon: "folder_open"
                mainText: Translation.tr("Choose Image")
                onClicked: imageDialog.open()
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.currentImagePath !== ""
                text: Translation.tr("Current image: %1").arg(root.currentImagePath)
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurfaceVariant
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: root.currentImagePath !== ""
                materialIcon: "delete"
                mainText: Translation.tr("Remove Image")
                onClicked: root.setImagePath("")
            }

            ContentSubsectionLabel {
                text: Translation.tr("Visual Options")
            }

            ConfigSelectionArray {
                currentValue: root.configEntry?.fitMode ?? "crop"
                onSelected: value => {
                    if (root.configEntry)
                        root.configEntry.fitMode = value;
                }
                options: [
                    { "displayName": Translation.tr("Crop to fill"), "value": "crop" },
                    { "displayName": Translation.tr("Fit whole image"), "value": "fit" }
                ]
            }

            ConfigSwitch {
                buttonIcon: "subtitles"
                text: Translation.tr("Show Caption or Badge")
                visible: root.configEntryName !== "photo"
                checked: {
                    let entry = Config.options.background.widgets[root.configEntryName];
                    return entry && entry.showOverlay !== undefined ? entry.showOverlay : true;
                }
                onCheckedChanged: {
                    if (root.configEntryName === "photo") return;
                    let entry = Config.options.background.widgets[root.configEntryName];
                    if (entry && entry.showOverlay !== undefined) {
                        entry.showOverlay = checked;
                    }
                }
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.enableShadows ?? true
                onCheckedChanged: {
                    Config.options.background.widgets.enableShadows = checked;
                }
            }

        }
    }
}
