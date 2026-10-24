pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Options for the vendored iRiS Visualizer canvas widget. Its config lives in the
// inir store under background.widgets.visualizer.*; the Ryoku skin, scale,
// opacity, placement and lock stay in WidgetMenu's generic rows.
Column {
    id: opts

    property string widget: ""
    readonly property var face: IrisRoster.byPrefix(opts.widget)
    readonly property string base: "background.widgets." + (opts.face ? opts.face.id : "")

    width: parent ? parent.width : 0
    spacing: Theme.s1

    function g(key, fb) { return Inir.Config.getNestedValue(opts.base + "." + key, fb); }
    function put(key, v) { Inir.Config.setNestedValue(opts.base + "." + key, v); }
    function cap(s) { return (s && s.length > 0) ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
    function cycle(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length]; }

    MenuSection { label: I18n.tr("Visualiser"); gloss: "音波" }
    MenuRow {
        label: I18n.tr("Type")
        value: opts.cap(String(opts.g("vizType", "bars")))
        closeOnTrigger: false
        onTriggered: opts.put("vizType", opts.cycle(["bars", "wave", "organic"], String(opts.g("vizType", "bars"))))
    }
    MenuRow {
        label: I18n.tr("Palette")
        value: opts.cap(String(opts.g("paletteMode", "cava")))
        closeOnTrigger: false
        onTriggered: opts.put("paletteMode", opts.cycle(["cava", "accent", "primary", "album"], String(opts.g("paletteMode", "cava"))))
    }
    MenuSlider {
        id: barCount
        visible: String(opts.g("vizType", "bars")) === "bars"
        label: I18n.tr("Bars")
        from: 8; to: 96; step: 1
        value: Number(opts.g("barCount", 48))
        valueText: Math.round(barCount.value)
        onMoved: (v) => opts.put("barCount", Math.round(v))
        onReleased: (v) => opts.put("barCount", Math.round(v))
    }
    MenuSlider {
        id: barSpacing
        visible: String(opts.g("vizType", "bars")) === "bars"
        label: I18n.tr("Bar spacing")
        from: 0; to: 8; step: 1
        value: Number(opts.g("barSpacing", 2))
        valueText: Math.round(barSpacing.value)
        onMoved: (v) => opts.put("barSpacing", Math.round(v))
        onReleased: (v) => opts.put("barSpacing", Math.round(v))
    }
    MenuSlider {
        id: fill
        label: I18n.tr("Fill ratio")
        from: 10; to: 100; step: 1
        value: Number(opts.g("fillRatio", 90))
        valueText: Math.round(fill.value) + "%"
        onMoved: (v) => opts.put("fillRatio", Math.round(v))
        onReleased: (v) => opts.put("fillRatio", Math.round(v))
    }
    MenuSlider {
        id: accent
        label: I18n.tr("Accent strength")
        from: 0; to: 100; step: 1
        value: Number(opts.g("accentStrength", 70))
        valueText: Math.round(accent.value) + "%"
        onMoved: (v) => opts.put("accentStrength", Math.round(v))
        onReleased: (v) => opts.put("accentStrength", Math.round(v))
    }
    MenuSlider {
        id: smooth
        label: I18n.tr("Smoothing")
        from: 0; to: 5; step: 1
        value: Number(opts.g("smoothing", 2))
        valueText: Math.round(smooth.value)
        onMoved: (v) => opts.put("smoothing", Math.round(v))
        onReleased: (v) => opts.put("smoothing", Math.round(v))
    }
    MenuSlider {
        id: barOp
        label: I18n.tr("Bar opacity")
        from: 0; to: 100; step: 1
        value: Number(opts.g("barOpacity", 100))
        valueText: Math.round(barOp.value) + "%"
        onMoved: (v) => opts.put("barOpacity", Math.round(v))
        onReleased: (v) => opts.put("barOpacity", Math.round(v))
    }
}
