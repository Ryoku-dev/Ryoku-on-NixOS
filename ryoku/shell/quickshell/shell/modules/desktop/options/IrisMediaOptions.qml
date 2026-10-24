pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Now Playing face: the player layout, synced
// lyrics, and the built-in visualiser. Lyrics reads through irisOption(); the
// visualiser knobs are the face's own raw keys.
Column {
    id: opts

    property string widget: ""
    readonly property var face: IrisRoster.byPrefix(opts.widget)
    readonly property string base: "background.widgets." + (opts.face ? opts.face.id : "")

    width: parent ? parent.width : 0
    spacing: Theme.s1

    function g(key, fb) { return Inir.Config.getNestedValue(opts.base + "." + key, fb); }
    function put(key, v) { Inir.Config.setNestedValue(opts.base + "." + key, v); }
    function toggle(key, fb) { opts.put(key, !opts.g(key, fb)); }
    function cap(s) { return (s && s.length > 0) ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
    function cycle(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length]; }

    MenuSection { label: I18n.tr("Media"); gloss: "音楽" }
    MenuRow {
        label: I18n.tr("Layout")
        value: opts.cap(String(opts.g("playerPreset", "full")))
        closeOnTrigger: false
        onTriggered: opts.put("playerPreset", opts.cycle(["full", "compact", "minimal"], String(opts.g("playerPreset", "full"))))
    }
    MenuRow {
        label: I18n.tr("Synced lyrics")
        value: opts.g("iris.lyrics", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("iris.lyrics", true); closeOnTrigger: false
        onTriggered: opts.toggle("iris.lyrics", true)
    }

    MenuSection { label: I18n.tr("Visualiser"); gloss: "音波" }
    MenuRow {
        label: I18n.tr("Type")
        value: opts.cap(String(opts.g("visualizerType", "wave")))
        closeOnTrigger: false
        onTriggered: opts.put("visualizerType", opts.cycle(["wave", "bars", "organic"], String(opts.g("visualizerType", "wave"))))
    }
    MenuRow {
        label: I18n.tr("Placement")
        value: opts.cap(String(opts.g("visualizerPosition", "bottom")))
        closeOnTrigger: false
        onTriggered: opts.put("visualizerPosition", opts.cycle(["bottom", "top", "fill", "none"], String(opts.g("visualizerPosition", "bottom"))))
    }
    MenuSlider {
        id: vizOp
        label: I18n.tr("Visualiser opacity")
        from: 0; to: 100; step: 1
        value: Number(opts.g("visualizerOpacity", 55))
        valueText: Math.round(vizOp.value) + "%"
        onMoved: (v) => opts.put("visualizerOpacity", Math.round(v))
        onReleased: (v) => opts.put("visualizerOpacity", Math.round(v))
    }
}
