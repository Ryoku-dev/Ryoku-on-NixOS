import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: row

    property var sheet: null
    property var rule: null
    property int position: 0
    property int total: 1
    property int foldoutIndex: -1
    property bool scheduleEnabled: true

    signal selectRequested()
    signal foldoutRequested(int idx)
    signal ruleEnabledToggled(bool wantEnabled)
    signal moveUp()
    signal moveDown()

    readonly property bool ruleEnabled: row.rule ? row.rule.enabled !== false : true

    implicitWidth: 200 * Theme.scale
    implicitHeight: bar.implicitHeight

    // At most one row stays open, following the index's selection.
    onFoldoutIndexChanged: {
        if (row.foldoutIndex === row.position) {
            if (!bar.expanded) bar.expanded = true
        } else if (bar.expanded) {
            bar.expanded = false
        }
    }

    StackBar {
        id: bar
        width: row.width
        title: (row.rule && row.rule.name) ? row.rule.name : I18n.tr("Unnamed rule")

        onToggled: (expanded) => {
            if (expanded) {
                row.foldoutRequested(row.position)
                row.selectRequested()
            } else {
                row.foldoutRequested(-1)
            }
        }

        Column {
            parent: bar.body
            width: parent.width
            spacing: 8 * Theme.scale

            Text {
                width: parent.width
                text: row.sheet && row.rule
                    ? (row.sheet.conditionSummary(row.rule.condition) + "  \u00b7  " + row.sheet.targetLabel(row.rule))
                    : ""
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontTiny
                color: Theme.withAlpha(Theme.surfaceText, row.ruleEnabled ? 0.44 : 0.28)
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }

            Row {
                width: parent.width
                spacing: 8 * Theme.scale

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("Rule state")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontMicro
                    color: Theme.withAlpha(Theme.surfaceText, 0.54)
                    renderType: Text.NativeRendering
                }
                Item {
                    width: parent.width - stateAction.width - reorder.width - parent.spacing * 2
                    height: 1
                }
                FolioAction {
                    id: stateAction
                    anchors.verticalCenter: parent.verticalCenter
                    fixedWidth: 58 * Theme.scale
                    label: row.ruleEnabled ? I18n.tr("On") : I18n.tr("Off")
                    active: row.scheduleEnabled && row.ruleEnabled
                    onTriggered: row.ruleEnabledToggled(!row.ruleEnabled)
                }
                Row {
                    id: reorder
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4 * Theme.scale
                    FolioAction {
                        fixedWidth: 30 * Theme.scale
                        glyph: "\uf077"
                        enabled: row.position > 0
                        onTriggered: row.moveUp()
                    }
                    FolioAction {
                        fixedWidth: 30 * Theme.scale
                        glyph: "\uf078"
                        enabled: row.position < row.total - 1
                        onTriggered: row.moveDown()
                    }
                }
            }
        }
    }
}
