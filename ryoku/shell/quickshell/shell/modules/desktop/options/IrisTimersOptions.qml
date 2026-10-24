pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Timers face.
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

    MenuSection { label: I18n.tr("Timers"); gloss: "計時" }
    MenuRow {
        label: I18n.tr("Style")
        value: opts.cap(String(opts.g("style", "cards")))
        closeOnTrigger: false
        onTriggered: opts.put("style", opts.cycle(["cards", "instrument"], String(opts.g("style", "cards"))))
    }
    MenuRow {
        label: I18n.tr("Vertical")
        value: opts.g("vertical", false) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("vertical", false); closeOnTrigger: false
        onTriggered: opts.toggle("vertical", false)
    }
    MenuRow {
        label: I18n.tr("Glow")
        value: opts.g("glow", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("glow", true); closeOnTrigger: false
        onTriggered: opts.toggle("glow", true)
    }
    MenuRow {
        label: I18n.tr("Progress")
        value: opts.g("showProgress", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showProgress", true); closeOnTrigger: false
        onTriggered: opts.toggle("showProgress", true)
    }
    MenuRow {
        label: I18n.tr("State")
        value: opts.g("showState", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showState", true); closeOnTrigger: false
        onTriggered: opts.toggle("showState", true)
    }
    MenuRow {
        label: I18n.tr("Hundredths")
        value: opts.g("showHundredths", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showHundredths", true); closeOnTrigger: false
        onTriggered: opts.toggle("showHundredths", true)
    }
}
