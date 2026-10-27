pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: root

    property string selectedStyle: "karuma"
    signal chose(string styleId)

    readonly property var styles: [
        { id: "karuma", name: I18n.tr("Karuma"), description: I18n.tr("The default Ryoku Nix bar."), recommended: true },
        { id: "orpheus", name: I18n.tr("Orpheus"), description: I18n.tr("A liquid bar that moves with your music.") },
        { id: "sumi", name: I18n.tr("Sumi"), description: I18n.tr("The monochrome painted frame.") },
        { id: "qsbar", name: I18n.tr("QS Bar"), description: I18n.tr("The full-colour wallpaper bar.") },
        { id: "nomarchy", name: I18n.tr("Nomarchy"), description: I18n.tr("Omarchy's bar with its plugin library.") },
        { id: "kairos", name: I18n.tr("Kairos"), description: I18n.tr("A clock island that grows with you.") },
        { id: "iris", name: I18n.tr("Shima"), description: I18n.tr("An edge island that morphs into tools.") },
        { id: "python", name: I18n.tr("Python"), description: I18n.tr("Pills that open into one stage.") }
    ]

    function styleName(styleId) {
        for (let i = 0; i < styles.length; i++) {
            if (styles[i].id === styleId)
                return styles[i].name
        }
        return ""
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.s4

        PageTitle {
            width: parent.width
            title: I18n.tr("Choose your edge")
            description: I18n.tr("Pick any bar to try it now. The desktop switches while this window stays open.")
        }

        BarPreviewStage {
            width: parent.width
            styleId: root.selectedStyle
            styleName: root.styleName(root.selectedStyle)
        }

        Grid {
            id: selectors
            width: parent.width
            columns: 4
            spacing: Tokens.s2

            Repeater {
                model: root.styles

                BarCard {
                    required property var modelData
                    width: Math.floor(
                        (selectors.width - selectors.spacing * (selectors.columns - 1))
                        / selectors.columns
                    )
                    styleId: modelData.id
                    name: modelData.name
                    description: modelData.description
                    recommended: modelData.recommended === true
                    selected: root.selectedStyle === modelData.id
                    onChosen: styleId => root.chose(styleId)
                }
            }
        }
    }
}
