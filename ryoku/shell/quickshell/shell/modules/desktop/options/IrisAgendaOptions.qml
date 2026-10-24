pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS "Up next" (upcoming events) face.
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

    MenuSection { label: I18n.tr("Up next"); gloss: "予定" }
    MenuRow {
        label: I18n.tr("Style")
        value: opts.cap(String(opts.g("style", "card")))
        closeOnTrigger: false
        onTriggered: opts.put("style", opts.cycle(["card", "instrument"], String(opts.g("style", "card"))))
    }
    MenuSlider {
        id: maxEv
        label: I18n.tr("Maximum events")
        from: 1; to: 12; step: 1
        value: Number(opts.g("maxEvents", 5))
        valueText: Math.round(maxEv.value)
        onMoved: (v) => opts.put("maxEvents", Math.round(v))
        onReleased: (v) => opts.put("maxEvents", Math.round(v))
    }
    MenuRow {
        label: I18n.tr("Date")
        value: opts.g("showDate", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showDate", true); closeOnTrigger: false
        onTriggered: opts.toggle("showDate", true)
    }
    MenuRow {
        label: I18n.tr("Time")
        value: opts.g("showTime", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showTime", true); closeOnTrigger: false
        onTriggered: opts.toggle("showTime", true)
    }
    MenuRow {
        label: I18n.tr("Group by day")
        value: opts.g("groupByDay", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("groupByDay", true); closeOnTrigger: false
        onTriggered: opts.toggle("groupByDay", true)
    }
    MenuRow {
        label: I18n.tr("Location")
        value: opts.g("showLocation", false) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showLocation", false); closeOnTrigger: false
        onTriggered: opts.toggle("showLocation", false)
    }
}
