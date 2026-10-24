pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import "PythonOpts.js" as PythonOpts

// Options for the Python clock face. The material analog and lumen dials carry
// a second hand upstream; the host panel exposes it (and drops it again for
// variants that have none) through the widget's <prefix>Opts JSON.
Column {
    id: opts

    property string widget: ""
    width: parent ? parent.width : 0
    spacing: Theme.s1

    readonly property string variant: Config[opts.widget + "Variant"] || "digital"
    readonly property bool hasSeconds: opts.variant === "materialAnalog" || opts.variant === "lumen"
    readonly property bool showSeconds: PythonOpts.read(Config, opts.widget).showSeconds !== false

    MenuSection { visible: opts.hasSeconds; label: I18n.tr("Clock"); gloss: "時計" }
    MenuRow {
        visible: opts.hasSeconds
        label: I18n.tr("Second hand")
        value: opts.showSeconds ? I18n.tr("On") : I18n.tr("Off")
        on: opts.showSeconds
        closeOnTrigger: false
        onTriggered: PythonOpts.put(Config, opts.widget, "showSeconds", !opts.showSeconds)
    }
}
