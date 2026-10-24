pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Profile (user card) face.
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

    MenuSection { label: I18n.tr("Profile"); gloss: "人物" }
    MenuRow {
        label: I18n.tr("Style")
        value: opts.cap(String(opts.g("style", "card")))
        closeOnTrigger: false
        onTriggered: opts.put("style", opts.cycle(["card", "instrument"], String(opts.g("style", "card"))))
    }
    MenuRow {
        label: I18n.tr("Picture")
        value: opts.g("showAvatar", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showAvatar", true); closeOnTrigger: false
        onTriggered: opts.toggle("showAvatar", true)
    }
    MenuRow {
        label: I18n.tr("Weather")
        value: opts.g("showWeather", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showWeather", true); closeOnTrigger: false
        onTriggered: opts.toggle("showWeather", true)
    }
    MenuRow {
        label: I18n.tr("Computer name")
        value: opts.g("showHostname", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showHostname", true); closeOnTrigger: false
        onTriggered: opts.toggle("showHostname", true)
    }
}
