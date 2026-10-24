pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Batteries face.
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

    MenuSection { label: I18n.tr("Batteries"); gloss: "電池" }
    MenuRow {
        label: I18n.tr("Display")
        value: opts.cap(String(opts.g("displayMode", "ring")))
        closeOnTrigger: false
        onTriggered: opts.put("displayMode", opts.cycle(["ring", "bars", "pill"], String(opts.g("displayMode", "ring"))))
    }
    MenuRow {
        label: I18n.tr("Time remaining")
        value: opts.g("showTime", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showTime", true); closeOnTrigger: false
        onTriggered: opts.toggle("showTime", true)
    }
    MenuRow {
        label: I18n.tr("Charge rate")
        value: opts.g("showRate", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showRate", true); closeOnTrigger: false
        onTriggered: opts.toggle("showRate", true)
    }
    MenuSlider {
        id: ring
        visible: String(opts.g("displayMode", "ring")) === "ring"
        label: I18n.tr("Ring size")
        from: 48; to: 120; step: 1
        value: Number(opts.g("ringSize", 72))
        valueText: Math.round(ring.value)
        onMoved: (v) => opts.put("ringSize", Math.round(v))
        onReleased: (v) => opts.put("ringSize", Math.round(v))
    }
}
