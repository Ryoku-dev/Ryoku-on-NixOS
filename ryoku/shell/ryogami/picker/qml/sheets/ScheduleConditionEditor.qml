import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: editor

    property var sheet: null

    readonly property var editing: editor.sheet ? editor.sheet.editing : ({ mode: "none", path: [] })
    readonly property var _rule: editor.sheet ? editor.sheet.currentRule : null
    readonly property var selNode: (editor.editing.mode === "node" && editor._rule && editor.sheet)
        ? editor.sheet.nodeAt(editor._rule.condition, editor.editing.path) : null
    readonly property bool selIsGroup: editor.selNode !== null && editor.selNode.block === undefined
    readonly property var _path: editor.editing.path

    implicitWidth: 200 * Theme.scale
    implicitHeight: stack.implicitHeight

    Item {
        id: stack
        width: parent.width
        implicitHeight: {
            if (editor.editing.mode === "add") return addFace.implicitHeight
            if (editor.selNode !== null) return editor.selIsGroup ? groupFace.implicitHeight : blockFace.implicitHeight
            return idleFace.implicitHeight
        }

        Column {
            id: addFace
            width: parent.width
            visible: editor.editing.mode === "add"
            spacing: 9 * Theme.scale

            Text {
                width: parent.width
                text: I18n.tr("What should this group check?")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontSmall
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
            Text {
                width: parent.width
                text: I18n.tr("Choose a condition, or add a nested group when this rule needs mixed all/any logic.")
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fs(8.6)
                color: Theme.withAlpha(Theme.surfaceText, 0.48)
                lineHeight: 1.35
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }

            Flow {
                width: parent.width
                spacing: 7 * Theme.scale

                Repeater {
                    model: editor.sheet ? editor.sheet.blockKinds : []
                    delegate: FolioAction {
                        required property var modelData
                        label: editor.sheet ? editor.sheet.blockKindName(modelData) : modelData
                        onTriggered: if (editor.sheet) editor.sheet.addBlock(editor._path, modelData)
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 7 * Theme.scale

                FolioAction {
                    label: I18n.tr("Nested group: match all")
                    glyph: "\uf067"
                    onTriggered: if (editor.sheet) editor.sheet.addGroup(editor._path, false)
                }
                FolioAction {
                    label: I18n.tr("Nested group: match any")
                    glyph: "\uf067"
                    onTriggered: if (editor.sheet) editor.sheet.addGroup(editor._path, true)
                }
            }
        }

        Column {
            id: blockFace
            width: parent.width
            visible: editor.selNode !== null && !editor.selIsGroup
            spacing: 11 * Theme.scale

            Loader {
                width: parent.width
                sourceComponent: {
                    if (!editor.selNode || editor.selIsGroup) return null
                    switch (editor.selNode.block) {
                        case "weekday": return weekdayComp
                        case "weather": return weatherComp
                        case "timewindow": return timewindowComp
                        case "timecmp": return timecmpComp
                        case "date": return dateComp
                        case "year": return yearComp
                        case "power": return powerComp
                        case "battery": return batteryComp
                        case "output": return outputComp
                        case "outputcount": return outputcountComp
                        case "raw": return rawComp
                    }
                    return null
                }
            }

            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.negated : false
                options: [
                    { value: false, label: I18n.tr("Must match") },
                    { value: true, label: I18n.tr("Must not match") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setNegated(editor._path, v) }
            }

            FolioDestructiveAction {
                fixedWidth: 150 * Theme.scale
                confirm: true
                label: I18n.tr("Remove condition")
                glyph: "\uf1f8"
                onTriggered: if (editor.sheet) editor.sheet.removeNode(editor._path)
            }
        }

        Column {
            id: groupFace
            width: parent.width
            visible: editor.selNode !== null && editor.selIsGroup
            spacing: 11 * Theme.scale

            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.op : "all"
                options: [
                    { value: "all", label: I18n.tr("Match all") },
                    { value: "any", label: I18n.tr("Match any") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setGroupOp(editor._path, v) }
            }
            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.negated : false
                options: [
                    { value: false, label: I18n.tr("Include this group") },
                    { value: true, label: I18n.tr("Exclude this group") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setNegated(editor._path, v) }
            }
            FolioAction {
                fixedWidth: 176 * Theme.scale
                label: I18n.tr("Add inside this group")
                glyph: "\uf067"
                onTriggered: if (editor.sheet) editor.sheet.editAdd(editor._path)
            }
            FolioDestructiveAction {
                visible: editor._path.length > 0
                fixedWidth: 140 * Theme.scale
                confirm: true
                label: I18n.tr("Remove group")
                glyph: "\uf1f8"
                onTriggered: if (editor.sheet) editor.sheet.removeNode(editor._path)
            }
        }

        Text {
            id: idleFace
            width: parent.width
            visible: editor.editing.mode !== "add" && editor.selNode === null
            text: I18n.tr("Select a condition or group above to edit it.")
            font.family: Theme.sans
            font.weight: Font.Normal
            font.pixelSize: Theme.fontSmall
            color: Theme.withAlpha(Theme.surfaceText, 0.46)
            wrapMode: Text.WordWrap
            renderType: Text.NativeRendering
        }
    }

    component Hint: Text {
        width: parent ? parent.width : 0
        font.family: Theme.sans
        font.weight: Font.Normal
        font.pixelSize: Theme.fs(8.5)
        color: Theme.withAlpha(Theme.surfaceText, 0.42)
        lineHeight: 1.35
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
    }

    component EndpointLabel: Text {
        font.family: Theme.sans
        font.weight: Font.Medium
        font.pixelSize: Theme.fontFine
        color: Theme.withAlpha(Theme.surfaceText, 0.52)
        renderType: Text.NativeRendering
    }

    Component {
        id: weekdayComp
        Flow {
            width: parent ? parent.width : 0
            spacing: 7 * Theme.scale
            Repeater {
                model: editor.sheet ? editor.sheet.weekdays : []
                delegate: FixedButton {
                    required property var modelData
                    label: editor.sheet ? editor.sheet.weekdayLabel(modelData) : modelData
                    active: editor.selNode && editor.selNode.days ? editor.selNode.days.indexOf(modelData) >= 0 : false
                    onTriggered: if (editor.sheet) editor.sheet.toggleVal(editor._path, "days", modelData, 1)
                }
            }
        }
    }

    Component {
        id: weatherComp
        Column {
            width: parent ? parent.width : 0
            spacing: 7 * Theme.scale
            Flow {
                width: parent.width
                spacing: 7 * Theme.scale
                Repeater {
                    model: editor.sheet ? editor.sheet.weatherTags : []
                    delegate: FixedButton {
                        required property var modelData
                        label: editor.sheet ? editor.sheet.weatherLabel(modelData) : modelData
                        active: editor.selNode && editor.selNode.tags ? editor.selNode.tags.indexOf(modelData) >= 0 : false
                        onTriggered: if (editor.sheet) editor.sheet.toggleVal(editor._path, "tags", modelData, 1)
                    }
                }
            }
            Hint { text: I18n.tr("Uses the weather location configured in Settings.") }
        }
    }

    Component {
        id: timewindowComp
        Column {
            width: parent ? parent.width : 0
            spacing: 11 * Theme.scale
            Column {
                width: parent.width
                spacing: 6 * Theme.scale
                EndpointLabel { text: I18n.tr("From") }
                ScheduleTimeEndpoint {
                    width: parent.width
                    value: editor.selNode ? (editor.selNode.from || "") : ""
                    onCommitted: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "from", v) }
                }
            }
            Column {
                width: parent.width
                spacing: 6 * Theme.scale
                EndpointLabel { text: I18n.tr("To") }
                ScheduleTimeEndpoint {
                    width: parent.width
                    value: editor.selNode ? (editor.selNode.to || "") : ""
                    onCommitted: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "to", v) }
                }
            }
        }
    }

    Component {
        id: timecmpComp
        Column {
            width: parent ? parent.width : 0
            spacing: 11 * Theme.scale
            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.op : ">="
                options: [
                    { value: ">=", label: I18n.tr("After") },
                    { value: "<", label: I18n.tr("Before") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "op", v) }
            }
            ScheduleTimeEndpoint {
                width: parent.width
                value: editor.selNode ? (editor.selNode.at || "") : ""
                onCommitted: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "at", v) }
            }
        }
    }

    Component {
        id: dateComp
        Column {
            width: parent ? parent.width : 0
            spacing: 7 * Theme.scale
            TextField {
                id: dateField
                width: parent.width
                variant: "field"
                placeholder: I18n.tr("12-25, 2026-12-25, or 07-01..07-14")
                text: editor.selNode ? (editor.selNode.value || "") : ""
                onCommitted: (t) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "value", t.trim()) }
                Connections {
                    target: editor
                    function onSelNodeChanged() {
                        if (!dateField.editing) dateField.text = editor.selNode ? (editor.selNode.value || "") : ""
                    }
                }
            }
            Hint { text: I18n.tr("Use MM-DD or YYYY-MM-DD, optionally as a range joined by .. . Recurring ranges may wrap the new year.") }
        }
    }

    Component {
        id: yearComp
        Column {
            width: parent ? parent.width : 0
            spacing: 9 * Theme.scale
            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.op : ""
                options: [
                    { value: "", label: I18n.tr("Exact") },
                    { value: ">=", label: I18n.tr("At least") },
                    { value: "<=", label: I18n.tr("At most") },
                    { value: ">", label: I18n.tr("After") },
                    { value: "<", label: I18n.tr("Before") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "op", v) }
            }
            TextField {
                id: yearField
                width: 120 * Theme.scale
                variant: "field"
                placeholder: I18n.tr("2026")
                text: editor.selNode ? (editor.selNode.value || "") : ""
                onCommitted: (t) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "value", t.trim()) }
                Connections {
                    target: editor
                    function onSelNodeChanged() {
                        if (!yearField.editing) yearField.text = editor.selNode ? (editor.selNode.value || "") : ""
                    }
                }
            }
        }
    }

    Component {
        id: powerComp
        ChoiceButtons {
            width: parent ? parent.width : 0
            value: editor.selNode ? editor.selNode.source : "battery"
            options: [
                { value: "battery", label: I18n.tr("Battery power") },
                { value: "external", label: I18n.tr("External power") }
            ]
            onSelected: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "source", v) }
        }
    }

    Component {
        id: batteryComp
        Column {
            width: parent ? parent.width : 0
            spacing: 9 * Theme.scale
            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.op : "<="
                options: [
                    { value: "", label: I18n.tr("Exactly") },
                    { value: ">=", label: I18n.tr("At least") },
                    { value: "<=", label: I18n.tr("At most") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "op", v) }
            }
            TextField {
                id: batteryField
                width: 100 * Theme.scale
                variant: "field"
                placeholder: I18n.tr("30")
                text: editor.selNode ? (editor.selNode.value || "") : ""
                onCommitted: (t) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "value", t.trim()) }
                Connections {
                    target: editor
                    function onSelNodeChanged() {
                        if (!batteryField.editing) batteryField.text = editor.selNode ? (editor.selNode.value || "") : ""
                    }
                }
            }
            Hint { text: I18n.tr("Percentage from the system battery. Unknown battery state fails closed.") }
        }
    }

    Component {
        id: outputComp
        Column {
            width: parent ? parent.width : 0
            spacing: 7 * Theme.scale
            TextField {
                id: outputField
                width: parent.width
                variant: "field"
                placeholder: I18n.tr("DP-1 or eDP-1")
                text: editor.selNode ? (editor.selNode.value || "") : ""
                onCommitted: (t) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "value", t.trim()) }
                Connections {
                    target: editor
                    function onSelNodeChanged() {
                        if (!outputField.editing) outputField.text = editor.selNode ? (editor.selNode.value || "") : ""
                    }
                }
            }
            Hint { text: I18n.tr("Match the exact connected output name. Negate this condition to match when it is absent.") }
        }
    }

    Component {
        id: outputcountComp
        Column {
            width: parent ? parent.width : 0
            spacing: 9 * Theme.scale
            ChoiceButtons {
                width: parent.width
                value: editor.selNode ? editor.selNode.op : ">="
                options: [
                    { value: "", label: I18n.tr("Exactly") },
                    { value: ">=", label: I18n.tr("At least") },
                    { value: "<=", label: I18n.tr("At most") }
                ]
                onSelected: (v) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "op", v) }
            }
            TextField {
                id: countField
                width: 100 * Theme.scale
                variant: "field"
                placeholder: I18n.tr("2")
                text: editor.selNode ? (editor.selNode.value || "") : ""
                onCommitted: (t) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "value", t.trim()) }
                Connections {
                    target: editor
                    function onSelNodeChanged() {
                        if (!countField.editing) countField.text = editor.selNode ? (editor.selNode.value || "") : ""
                    }
                }
            }
            Hint { text: I18n.tr("At least 2 displays is the usual docked-laptop rule.") }
        }
    }

    Component {
        id: rawComp
        Column {
            width: parent ? parent.width : 0
            spacing: 7 * Theme.scale
            TextField {
                id: rawField
                width: parent.width
                variant: "field"
                placeholder: I18n.tr("Raw condition")
                text: editor.selNode ? (editor.selNode.value || "") : ""
                onCommitted: (t) => { if (editor.sheet) editor.sheet.setPredField(editor._path, "value", t.trim()) }
                Connections {
                    target: editor
                    function onSelNodeChanged() {
                        if (!rawField.editing) rawField.text = editor.selNode ? (editor.selNode.value || "") : ""
                    }
                }
            }
            Hint { text: I18n.tr("This condition is preserved exactly as typed.") }
        }
    }
}
