import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets
import stage.services

ColumnLayout {
    id: root

    property bool innerShadow: false

    Layout.fillWidth: true
    spacing: 4

    ContentSubsectionLabel {
        text: Translation.tr("Visual Options")
    }

    ConfigSwitch {
        buttonIcon: "wb_sunny"
        text: Translation.tr("Enable Shadows")
        checked: Config.options.background.widgets.enableShadows ?? true
        onCheckedChanged: Config.options.background.widgets.enableShadows = checked
    }

    ConfigSwitch {
        visible: root.innerShadow
        buttonIcon: "blur_on"
        text: Translation.tr("Enable Inner Shadows")
        checked: root.innerShadow
            && (Config.options.background.widgets.enableInnerShadow ?? true)
        onCheckedChanged: {
            if (root.innerShadow)
                Config.options.background.widgets.enableInnerShadow = checked;
        }
    }
}
