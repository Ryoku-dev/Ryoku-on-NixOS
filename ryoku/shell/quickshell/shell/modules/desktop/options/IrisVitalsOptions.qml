pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Vitals (system monitor) face: the readout
// style and which metrics the face graphs.
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

    MenuSection { label: I18n.tr("Vitals"); gloss: "計測" }
    MenuRow {
        label: I18n.tr("Display")
        value: opts.cap(String(opts.g("displayMode", "bars")))
        closeOnTrigger: false
        onTriggered: opts.put("displayMode", opts.cycle(["bars", "graph", "rings", "tiles"], String(opts.g("displayMode", "bars"))))
    }
    MenuSlider {
        id: bars
        visible: String(opts.g("displayMode", "bars")) === "bars"
        label: I18n.tr("Bars")
        from: 8; to: 64; step: 1
        value: Number(opts.g("barCount", 32))
        valueText: Math.round(bars.value)
        onMoved: (v) => opts.put("barCount", Math.round(v))
        onReleased: (v) => opts.put("barCount", Math.round(v))
    }
    MenuRow {
        label: I18n.tr("Labels")
        value: opts.g("showLabels", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showLabels", true); closeOnTrigger: false
        onTriggered: opts.toggle("showLabels", true)
    }

    MenuSection { label: I18n.tr("Metrics"); gloss: "指標" }
    MenuRow {
        label: I18n.tr("CPU")
        value: opts.g("showCpu", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showCpu", true); closeOnTrigger: false
        onTriggered: opts.toggle("showCpu", true)
    }
    MenuRow {
        label: I18n.tr("Memory")
        value: opts.g("showMemory", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showMemory", true); closeOnTrigger: false
        onTriggered: opts.toggle("showMemory", true)
    }
    MenuRow {
        label: I18n.tr("GPU")
        value: opts.g("showGpu", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showGpu", true); closeOnTrigger: false
        onTriggered: opts.toggle("showGpu", true)
    }
    MenuRow {
        label: I18n.tr("CPU heat")
        value: opts.g("showTemp", false) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showTemp", false); closeOnTrigger: false
        onTriggered: opts.toggle("showTemp", false)
    }
    MenuRow {
        label: I18n.tr("GPU heat")
        value: opts.g("showGpuTemp", false) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showGpuTemp", false); closeOnTrigger: false
        onTriggered: opts.toggle("showGpuTemp", false)
    }
    MenuRow {
        label: I18n.tr("Disk")
        value: opts.g("showDisk", false) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("showDisk", false); closeOnTrigger: false
        onTriggered: opts.toggle("showDisk", false)
    }
}
