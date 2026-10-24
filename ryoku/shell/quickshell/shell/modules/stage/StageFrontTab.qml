pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import stage.modules.common as StageIsland
import "Singletons" as StageCfg

Column {
    id: root

    required property string mode

    width: parent ? parent.width : 0
    spacing: Tokens.s4

    readonly property var cfg: StageCfg.Config
    readonly property var provider: StageIsland.Config.widgetProvider
    readonly property var visibleRows: root.provider
        ? (root.provider.rows || []).filter(row => row.enabled) : []

    function liftId(row) {
        const id = String(row && row.id || "");
        return id.indexOf("plugin:") === 0 ? id.slice(7) : id;
    }

    Empty {
        visible: root.visibleRows.length === 0
        width: parent.width
        caption: I18n.tr("Place a widget or visualizer, then return here to choose its depth.")
    }

    SettingCard {
        visible: root.visibleRows.length > 0
        width: parent.width
        title: I18n.tr("DESKTOP LAYERS")
        kana: "前面"
        summary: I18n.tr("%1 placed").arg(root.visibleRows.length)
        collapsible: false

        Repeater {
            model: root.visibleRows

            delegate: SettingRow {
                id: frontRow

                required property var modelData
                required property int index
                readonly property string key: root.liftId(frontRow.modelData)

                width: parent.width
                divider: index > 0
                label: I18n.tr(String(modelData.label || modelData.id))
                desc: modelData.id.indexOf("plugin:") === 0
                    ? I18n.tr("Plugin tile keyed by %1").arg(frontRow.key)
                    : I18n.tr("Placed desktop item")
                controlWidth: Tokens.s7 + Tokens.s2

                Sw {
                    anchors.right: parent.right
                    on: root.cfg.isFront(root.mode, frontRow.key)
                    onToggled: value => root.cfg.setFront(root.mode, frontRow.key, value)
                }
            }
        }
    }
}
