import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: panel

    property var sheet: null
    property var rules: []
    property bool scheduleEnabled: true
    property int selectedIndex: -1
    property int foldoutIndex: -1
    property bool loaded: false

    property SettingValue _applyOnStart: SettingValue { key: "schedule.applyOnStart" }
    property SettingValue _lat: SettingValue { key: "schedule.latitude" }
    property SettingValue _lon: SettingValue { key: "schedule.longitude" }

    function _str(v) { return (v !== undefined && v !== null) ? String(v) : "" }

    anchors.fill: parent

    ColumnLayout {
        anchors.fill: parent
        spacing: 18 * Theme.scale

        Column {
            Layout.fillWidth: true
            spacing: 8 * Theme.scale

            FolioRule { width: parent.width; alpha: 0.5 }

            Text {
                text: I18n.tr("Schedule state")
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.7)
                renderType: Text.NativeRendering
            }
            ChoiceButtons {
                width: parent.width
                value: panel.scheduleEnabled
                options: [
                    { value: true, label: I18n.tr("Enabled") },
                    { value: false, label: I18n.tr("Disabled") }
                ]
                onSelected: (v) => { if (panel.sheet) panel.sheet.setScheduleEnabled(v) }
            }
            Text {
                width: parent.width
                text: panel.scheduleEnabled ? I18n.tr("This ordered rule stack is active.")
                                    : I18n.tr("Rules stay saved, but none of them will run.")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                lineHeight: 1.35
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
        }

        Column {
            Layout.fillWidth: true
            spacing: 8 * Theme.scale

            FolioRule { width: parent.width; alpha: 0.5 }

            Text {
                text: I18n.tr("On startup")
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.7)
                renderType: Text.NativeRendering
            }
            ChoiceButtons {
                width: parent.width
                value: panel._applyOnStart.value === true
                options: [
                    { value: true, label: I18n.tr("Apply on startup") },
                    { value: false, label: I18n.tr("Leave last wallpaper") }
                ]
                onSelected: (v) => Settings.set("schedule.applyOnStart", v)
            }

            Text {
                topPadding: 4 * Theme.scale
                text: I18n.tr("Location")
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.7)
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: I18n.tr("Used for sunrise/sunset times and for weather conditions.")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                lineHeight: 1.35
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
            Row {
                width: parent.width
                spacing: 7 * Theme.scale
                TextField {
                    id: latField
                    width: (parent.width - parent.spacing) / 2
                    variant: "field"
                    placeholder: I18n.tr("59.33")
                    text: panel._str(panel._lat.value)
                    onCommitted: (t) => Settings.set("schedule.latitude", t.trim())
                    Connections {
                        target: panel._lat
                        function onValueChanged() { if (!latField.editing) latField.text = panel._str(panel._lat.value) }
                    }
                }
                TextField {
                    id: lonField
                    width: (parent.width - parent.spacing) / 2
                    variant: "field"
                    placeholder: I18n.tr("18.06")
                    text: panel._str(panel._lon.value)
                    onCommitted: (t) => Settings.set("schedule.longitude", t.trim())
                    Connections {
                        target: panel._lon
                        function onValueChanged() { if (!lonField.editing) lonField.text = panel._str(panel._lon.value) }
                    }
                }
            }
        }

        Flickable {
            id: listFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: listCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: listCol
                width: listFlick.width
                spacing: 4 * Theme.scale

                Repeater {
                    model: panel.rules

                    delegate: ScheduleRuleRow {
                        required property var modelData
                        required property int index

                        width: listCol.width
                        sheet: panel.sheet
                        rule: modelData
                        position: index
                        total: panel.rules.length
                        foldoutIndex: panel.foldoutIndex
                        scheduleEnabled: panel.scheduleEnabled

                        onSelectRequested: if (panel.sheet) panel.sheet.selectRule(index)
                        onFoldoutRequested: (i) => { if (panel.sheet) panel.sheet.foldoutIndex = i }
                        onRuleEnabledToggled: (want) => { if (panel.sheet) panel.sheet.setRuleEnabled(index, want) }
                        onMoveUp: if (panel.sheet) panel.sheet.moveRule(index, -1)
                        onMoveDown: if (panel.sheet) panel.sheet.moveRule(index, 1)
                    }
                }

                Column {
                    width: parent.width
                    spacing: 4 * Theme.scale
                    visible: panel.loaded && panel.rules.length === 0
                    topPadding: 14 * Theme.scale

                    Text {
                        text: I18n.tr("No schedule rules")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontLabel
                        color: Theme.surfaceText
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: I18n.tr("Create one below to begin.")
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontMini
                        color: Theme.withAlpha(Theme.surfaceText, 0.46)
                        renderType: Text.NativeRendering
                    }
                }
            }
        }

        Column {
            Layout.fillWidth: true
            spacing: 9 * Theme.scale

            FolioRule { width: parent.width; alpha: 0.5 }

            Text {
                text: I18n.tr("New rule")
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.7)
                renderType: Text.NativeRendering
            }
            FolioAction {
                width: parent.width
                fixedWidth: parent.width
                label: I18n.tr("Create rule")
                glyph: "\uf067"
                onTriggered: if (panel.sheet) panel.sheet.addRule()
            }
        }
    }
}
