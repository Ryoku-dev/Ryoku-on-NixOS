pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import "../iris/IrisRoster.js" as IrisRoster

// Face options for the vendored iRiS Clock face. The Ryoku skin, size preset,
// background, scale, opacity, placement and lock are WidgetMenu's generic rows;
// this adds the face's own choices. The face reads these through irisOption(),
// so they persist under the widget's iris.* subtree in the shared inir store.
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

    MenuSection { label: I18n.tr("Clock"); gloss: "時計" }
    MenuRow {
        label: I18n.tr("Face")
        value: String(opts.g("iris.face", "analog")) === "digital" ? I18n.tr("Digital") : I18n.tr("Analog")
        closeOnTrigger: false
        onTriggered: opts.put("iris.face", String(opts.g("iris.face", "analog")) === "digital" ? "analog" : "digital")
    }
    MenuRow {
        label: I18n.tr("Second hand")
        value: opts.g("iris.seconds", true) ? I18n.tr("On") : I18n.tr("Off")
        on: opts.g("iris.seconds", true)
        closeOnTrigger: false
        onTriggered: opts.toggle("iris.seconds", true)
    }
}
