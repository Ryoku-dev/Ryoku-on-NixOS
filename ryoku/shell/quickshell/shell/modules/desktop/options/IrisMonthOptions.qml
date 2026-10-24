pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Calendar (month) face.
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

    MenuSection { label: I18n.tr("Calendar"); gloss: "暦" }
    MenuRow {
        label: I18n.tr("Style")
        value: opts.cap(String(opts.g("style", "card")))
        closeOnTrigger: false
        onTriggered: opts.put("style", opts.cycle(["card", "instrument"], String(opts.g("style", "card"))))
    }
    MenuRow {
        label: I18n.tr("Week starts")
        value: Number(opts.g("weekStart", 1)) === 0 ? I18n.tr("Sunday") : I18n.tr("Monday")
        closeOnTrigger: false
        onTriggered: opts.put("weekStart", Number(opts.g("weekStart", 1)) === 0 ? 1 : 0)
    }
    MenuRow {
        label: I18n.tr("Adjacent days")
        value: opts.g("showAdjacentDays", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showAdjacentDays", true); closeOnTrigger: false
        onTriggered: opts.toggle("showAdjacentDays", true)
    }
    MenuRow {
        label: I18n.tr("Ruled grid")
        value: opts.g("instrumentRule", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("instrumentRule", true); closeOnTrigger: false
        onTriggered: opts.toggle("instrumentRule", true)
    }
}
