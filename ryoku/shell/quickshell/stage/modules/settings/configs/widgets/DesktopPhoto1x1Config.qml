import QtQuick
import QtQuick.Layouts
import Ryoku.Ui as RyokuUi
import stage.services
import stage.modules.common
import stage.modules.common.widgets
ContentPage {
    id: root
    forceWidth: false

    readonly property var configEntry: Config.options.background.widgets.photo_1x1
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
            topLeftRadius:    Appearance.rounding.full
            topRightRadius:   Appearance.rounding.full
            bottomLeftRadius: Appearance.rounding.full
            bottomRightRadius:Appearance.rounding.full
            colBackground:      Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple:          Appearance.colors.colSecondaryContainerActive
            MaterialSymbol {
                anchors.centerIn: parent
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
            onClicked: root.goBack()
        }

        StyledText {
            text: Translation.tr("Photo 1x1 Widget Options")
            font.pixelSize: Appearance.font.pixelSize.large
            font.family:    Appearance.font.family.title
            color: Appearance.colors.colOnLayer0
        }
    }

    ContentSection {
        title: Translation.tr("Photo Settings")
        icon: "image"

        Item {
            Layout.fillWidth: true
            implicitHeight: 250
            visible: !Config.isWidgetActive("photo_1x1")

            PagePlaceholder {
                anchors.fill: parent
                icon:    "image"
                shape:   MaterialShape.Shape.Circle
                title:       Translation.tr("Photo 1x1 disabled")
                description: Translation.tr("Enable Photo 1x1 in Desktop Widgets settings to configure options.")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: Config.isWidgetActive("photo_1x1")

            // ── Photo Selection ──────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Photo File") }

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
                mainText: Translation.tr("Remove Custom Image")
                onClicked: root.setImagePath("")
            }

            // ── Material Shape Selection ─────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Material Shape") }

            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.photo_1x1.backgroundShape ?? "Cookie9Sided"
                onSelected: value => Config.options.background.widgets.photo_1x1.backgroundShape = value
                options: ([
                    "Cookie9Sided", "Cookie12Sided", "Circle", "Rectangle", "Clover4Leaf", "Burst",
                    "Heart", "Bun", "Flower", "Puffy", "PuffyDiamond", "Sunny",
                    "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Ghostish",
                    "Clover8Leaf", "SoftBurst", "Boom", "SoftBoom", "Gem", "Diamond",
                    "Pentagon", "Square", "Arch", "Fan", "Arrow", "SemiCircle",
                    "Oval", "Pill", "Triangle", "Slanted", "ClamShell", "PixelCircle", "PixelTriangle"
                ]).map((shapeName) => {
                    return {
                        "displayName": "",
                        "shape": shapeName,
                        "value": shapeName
                    };
                })
            }

            // ── Size & Appearance ────────────────────────────────────────────
            ContentSubsectionLabel { text: Translation.tr("Size & Appearance") }

            ConfigSelectionArray {
                currentValue: root.configEntry?.fitMode ?? "crop"
                onSelected: value => root.configEntry.fitMode = value
                options: [
                    { "displayName": Translation.tr("Crop to fill"), "value": "crop" },
                    { "displayName": Translation.tr("Fit whole image"), "value": "fit" }
                ]
            }

            ConfigSlider {
                buttonIcon: "aspect_ratio"
                text:  Translation.tr("Widget Size")
                value: Config.options.background.widgets.photo_1x1.widgetSize ?? 100
                from: 50; to: 200; stepSize: 10
                onValueChanged: Config.options.background.widgets.photo_1x1.widgetSize = value
            }

            ConfigSwitch {
                buttonIcon: "wb_sunny"
                text: Translation.tr("Enable Shadows")
                checked: Config.options.background.widgets.enableShadows ?? true
                onCheckedChanged: Config.options.background.widgets.enableShadows = checked
            }
        }
    }
}
