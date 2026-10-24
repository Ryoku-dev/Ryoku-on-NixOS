import QtQuick
import Ryoku.Ui.Singletons

// folder is prefix-matched: "*" all, "" the root, "a/b" that branch.
BarMenu {
    id: fm

    required property LibraryView view

    readonly property bool engaged: fm.view && fm.view.folder !== "*" && fm.view.folder !== undefined
    property var _folders: []
    // Only a library with subfolders has anything to pick between.
    readonly property bool hasFolders: fm._folders.length > 0

    glyph: "\u{f024b}"
    label: fm._label()
    active: fm.engaged
    panelWidth: 220
    maxLabelWidth: 130

    function _rebuild() {
        fm._folders = fm.view ? Library.folders(fm.view.collection) : []
    }
    Component.onCompleted: fm._rebuild()
    Connections {
        target: fm.view
        ignoreUnknownSignals: true
        function onCollectionChanged() { fm._rebuild() }
    }
    Connections {
        target: Library
        function onChanged(collection) {
            if (fm.view && collection === fm.view.collection) fm._rebuild()
        }
    }

    function _label() {
        if (!fm.view) return I18n.tr("Main")
        var f = fm.view.folder
        if (f === "*") return I18n.tr("All folders")
        if (f === "" || f === undefined) return I18n.tr("Main")
        return f
    }
    function _pick(value) {
        if (fm.view) fm.view.folder = value
        fm.close()
    }

    Repeater {
        model: {
            var base = [{ label: I18n.tr("All folders"), value: "*", glyph: "\u{f0253}" },
                        { label: I18n.tr("Main"), value: "", glyph: "\u{f024b}" }]
            for (var i = 0; i < fm._folders.length; ++i)
                base.push({ label: fm._folders[i], value: fm._folders[i], glyph: "\u{f0770}" })
            return base
        }
        delegate: MenuRow {
            required property var modelData
            glyph: modelData.glyph
            label: modelData.label
            selected: fm.view && fm.view.folder === modelData.value
            onChosen: fm._pick(modelData.value)
        }
    }
}
