pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Weather face: presentation, the shape used
// by the Shape style, and which readings the face shows. Wrapper chrome (skin,
// size preset, background, scale, opacity, placement, lock) stays in WidgetMenu.
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

    readonly property var styles: ["pill", "card", "detail", "dial"]
    function styleLabel(v) {
        return v === "pill" ? I18n.tr("Shape") : v === "dial" ? I18n.tr("Instrument") : opts.cap(v);
    }
    readonly property var shapes: ["pill", "circle", "oval", "diamond", "heart", "flower", "cookie4", "sunny", "clover", "softBurst", "gem", "puffy"]
    function shapeLabel(v) {
        return v === "cookie4" ? I18n.tr("Cookie") : v === "softBurst" ? I18n.tr("Burst") : opts.cap(v);
    }

    MenuSection { label: I18n.tr("Weather"); gloss: "天気" }
    MenuRow {
        label: I18n.tr("Style")
        value: opts.styleLabel(String(opts.g("style", "pill")))
        closeOnTrigger: false
        onTriggered: opts.put("style", opts.cycle(opts.styles, String(opts.g("style", "pill"))))
    }
    MenuRow {
        visible: String(opts.g("style", "pill")) === "pill"
        label: I18n.tr("Shape")
        value: opts.shapeLabel(String(opts.g("shape", "pill")))
        closeOnTrigger: false
        onTriggered: opts.put("shape", opts.cycle(opts.shapes, String(opts.g("shape", "pill"))))
    }

    MenuSection { label: I18n.tr("Show"); gloss: "表示" }
    MenuRow {
        label: I18n.tr("Temperature")
        value: opts.g("showTemp", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showTemp", true); closeOnTrigger: false
        onTriggered: opts.toggle("showTemp", true)
    }
    MenuRow {
        label: I18n.tr("Icon")
        value: opts.g("showIcon", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showIcon", true); closeOnTrigger: false
        onTriggered: opts.toggle("showIcon", true)
    }
    MenuRow {
        label: I18n.tr("Condition")
        value: opts.g("showCondition", false) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showCondition", false); closeOnTrigger: false
        onTriggered: opts.toggle("showCondition", false)
    }
    MenuRow {
        label: I18n.tr("Metrics")
        value: opts.g("showMetrics", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showMetrics", true); closeOnTrigger: false
        onTriggered: opts.toggle("showMetrics", true)
    }
    MenuRow {
        label: I18n.tr("Sun path")
        value: opts.g("showSunPath", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showSunPath", true); closeOnTrigger: false
        onTriggered: opts.toggle("showSunPath", true)
    }
    MenuRow {
        label: I18n.tr("Sun times")
        value: opts.g("showSunTimes", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showSunTimes", true); closeOnTrigger: false
        onTriggered: opts.toggle("showSunTimes", true)
    }
    MenuRow {
        label: I18n.tr("Location")
        value: opts.g("showLocation", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showLocation", true); closeOnTrigger: false
        onTriggered: opts.toggle("showLocation", true)
    }
}
