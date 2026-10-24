pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir

// Right-click options for the vendored iRiS "Editorial" canvas widget. Every
// control writes the widget's own inir config on the daemon's single settings
// path (inir.background.widgets.editorial.*), the store the widget reads, so the
// card re-renders live. Editorial carries no preset logic, so each value is a
// plain write.
Column {
    id: opts

    property string widget: ""

    readonly property string path: "background.widgets.editorial"

    width: parent ? parent.width : 0
    spacing: Theme.s1

    function g(key, fallback) { return Inir.Config.getNestedValue(opts.path + "." + key, fallback); }
    function put(key, value) { Inir.Config.setNestedValue(opts.path + "." + key, value); }
    function cap(s) { return (s && s.length > 0) ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
    function cycle(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length]; }

    // ── Content ──────────────────────────────────────────────
    MenuSection { label: I18n.tr("Content"); gloss: "内容" }
    MenuTextField {
        label: I18n.tr("Title")
        placeholder: I18n.tr("Title")
        text: String(opts.g("title", "Make room for wonder."))
        onCommitted: (v) => opts.put("title", v)
    }
    MenuTextField {
        label: I18n.tr("Caption")
        placeholder: I18n.tr("Caption")
        text: String(opts.g("caption", "A LITTLE EVERY DAY"))
        onCommitted: (v) => opts.put("caption", v)
    }
    MenuTextField {
        label: I18n.tr("Footer")
        placeholder: I18n.tr("Footer")
        text: String(opts.g("footer", "YOUR OWN PERSPECTIVE"))
        onCommitted: (v) => opts.put("footer", v)
    }

    // ── Style ────────────────────────────────────────────────
    MenuSection { label: I18n.tr("Style"); gloss: "体裁" }
    MenuRow {
        label: I18n.tr("Composition")
        value: opts.cap(String(opts.g("style", "poster")))
        closeOnTrigger: false
        onTriggered: opts.put("style", opts.cycle(["poster", "quote", "label"], String(opts.g("style", "poster"))))
    }
    MenuRow {
        label: I18n.tr("Decorative accents")
        value: opts.g("showAccent", true) ? "On" : "Off"
        on: opts.g("showAccent", true)
        closeOnTrigger: false
        onTriggered: opts.put("showAccent", !opts.g("showAccent", true))
    }

    // ── Size ─────────────────────────────────────────────────
    MenuSection { label: I18n.tr("Size"); gloss: "寸法" }
    MenuSlider {
        id: cwSlider
        label: I18n.tr("Width")
        from: 180; to: 900; step: 20
        value: Number(opts.g("contentWidth", 360))
        valueText: Math.round(cwSlider.value)
        onMoved: (v) => opts.put("contentWidth", Math.round(v))
        onReleased: (v) => opts.put("contentWidth", Math.round(v))
    }
    MenuSlider {
        id: chSlider
        label: I18n.tr("Height")
        from: 140; to: 900; step: 20
        value: Number(opts.g("contentHeight", 240))
        valueText: Math.round(chSlider.value)
        onMoved: (v) => opts.put("contentHeight", Math.round(v))
        onReleased: (v) => opts.put("contentHeight", Math.round(v))
    }
}
