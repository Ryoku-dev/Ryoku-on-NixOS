import QtQuick
import Ryoku.Ui.Singletons

Column {
    id: chips

    property string provider: ""
    property var state: ({})
    property var sources: null
    property var collections: []

    signal changed(var next)

    spacing: 13 * Theme.scale
    width: parent ? parent.width : implicitWidth

    readonly property var model: {
        if (!chips.sources || chips.provider.length === 0)
            return []
        var ctx = { collections: chips.collections }
        var defs = chips.sources.sections(chips.provider)
        var out = []
        for (var i = 0; i < defs.length; ++i) {
            var built = defs[i].build(chips.state, ctx) || []
            if (built.length > 0 || defs[i].input)
                out.push({ group: defs[i].group, chips: built, input: defs[i].input || null })
        }
        return out
    }

    function _copy() { return JSON.parse(JSON.stringify(chips.state)) }

    function _isActive(chip) {
        if (chip.kind === "action")
            return false
        if (chip.kind === "bool")
            return chips.state[chip.key] === true
        if (chip.kind === "swatch")
            return chips.state.colour === chip.index
        if (chip.kind === "multi") {
            var arr = chips.state[chip.key] || []
            return chip.value === "" ? arr.length === 0 : arr.indexOf(chip.value) >= 0
        }
        if (chip.toggleMode)
            return false
        return chips.state[chip.key] === chip.value
    }

    function _tap(chip) {
        if (chip.kind === "action") {
            var after = chips.sources.act(chips.provider, chip, chips._copy())
            if (after)
                chips.changed(after)
            return
        }
        var s = chips._copy()
        if (chip.kind === "bool") {
            s[chip.key] = !s[chip.key]
        } else if (chip.kind === "swatch") {
            s.colour = (s.colour === chip.index) ? -1 : chip.index
        } else if (chip.kind === "multi") {
            var arr = (s[chip.key] || []).slice()
            if (chip.value === "") {
                arr = []
            } else {
                var at = arr.indexOf(chip.value)
                if (at >= 0) arr.splice(at, 1)
                else { arr.push(chip.value); var any = arr.indexOf(""); if (any >= 0) arr.splice(any, 1) }
            }
            s[chip.key] = arr
        } else {
            s[chip.key] = chip.value
        }
        chips.changed(s)
    }

    // The source validates the text and returns the next state, or null to refuse it.
    function _submit(input, text) {
        return chips.sources.submit(chips.provider, input, text, chips._copy())
    }

    Repeater {
        model: chips.model
        delegate: Column {
            id: section
            required property var modelData
            width: chips.width
            spacing: 5 * Theme.scale

            SectionLabel {
                width: parent.width
                text: section.modelData.group
            }

            Flow {
                width: parent.width
                spacing: 3 * Theme.scale
                Repeater {
                    model: modelData.chips
                    delegate: BrowserChip {
                        required property var modelData
                        kind: modelData.kind === "order" ? "order"
                            : modelData.kind === "swatch" ? "swatch" : "plain"
                        label: modelData.label !== undefined ? modelData.label : ""
                        swatchIndex: modelData.index !== undefined ? modelData.index : 0
                        swatchInner: modelData.kind === "swatch" && chips.sources
                            ? chips.sources.swatchColor(modelData.index, false) : "gray"
                        swatchInnerActive: modelData.kind === "swatch" && chips.sources
                            ? chips.sources.swatchColor(modelData.index, true) : "white"
                        active: chips._isActive(modelData)
                        onClicked: chips._tap(modelData)
                    }
                }
            }

            Loader {
                width: parent.width
                active: !!section.modelData.input
                visible: active
                sourceComponent: BrowserChipField {
                    width: parent ? parent.width : 0
                    placeholder: section.modelData.input.placeholder || ""
                    glyph: section.modelData.input.glyph || ""
                    // The new state rebuilds this section, so the field clears before it is emitted.
                    onCommitted: function(text) {
                        var next = chips._submit(section.modelData.input, text)
                        if (!next) {
                            reject()
                            return
                        }
                        clear()
                        chips.changed(next)
                    }
                }
            }
        }
    }
}
