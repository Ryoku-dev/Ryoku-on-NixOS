import QtQuick
import Ryoku.Ui.Singletons

// The seven orders in one list; the trigger names the one in use.
BarMenu {
    id: sm

    required property LibraryView view
    // Each order can be hidden from the list in Settings > Filter & Search.
    property var shown: function (key) { return true }

    readonly property var orders: [
        { value: "date", glyph: "\u{f00f0}", label: I18n.tr("Newest"), key: "filterBar.show.sort.date" },
        { value: "recent", glyph: "\u{f02da}", label: I18n.tr("Recently applied"), key: "filterBar.show.sort.recent" },
        { value: "color", glyph: "\u{f03d8}", label: I18n.tr("By colour"), key: "filterBar.show.sort.color" },
        { value: "pop", glyph: "\u{f0238}", label: I18n.tr("Colour pop"), key: "filterBar.show.sort.pop" },
        { value: "richness", glyph: "\u{f0b74}", label: I18n.tr("Colourful"), key: "filterBar.show.sort.richness" },
        { value: "minimalist", glyph: "\u{f0764}", label: I18n.tr("Minimalist"), key: "filterBar.show.sort.minimalist" },
        { value: "res", glyph: "\u{f0a24}", label: I18n.tr("Highest resolution"), key: "filterBar.show.sort.res" }
    ]
    readonly property var current: {
        var v = sm.view ? sm.view.sort : ""
        for (var i = 0; i < sm.orders.length; ++i)
            if (sm.orders[i].value === v) return sm.orders[i]
        return sm.orders[2]
    }
    readonly property int shownCount: {
        var n = 0
        for (var i = 0; i < sm.orders.length; ++i)
            if (sm.shown(sm.orders[i].key)) n++
        return n
    }

    glyph: sm.current.glyph
    label: sm.current.label
    tooltip: I18n.tr("Order")
    panelWidth: 210

    Repeater {
        model: sm.orders
        delegate: MenuRow {
            required property var modelData
            visible: sm.shown(modelData.key)
            height: visible ? implicitHeight : 0
            glyph: modelData.glyph
            label: modelData.label
            selected: sm.view && sm.view.sort === modelData.value
            onChosen: {
                if (sm.view) sm.view.sort = modelData.value
                sm.close()
            }
        }
    }
}
