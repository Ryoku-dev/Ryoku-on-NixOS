pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir

// Right-click options for the vendored iRiS "Image converter" canvas widget. It
// converts images dropped onto it; its one setting is the output format, written
// to the widget's own inir config on the daemon's single settings path
// (inir.background.widgets.imageConverter.selectedFormat), the store the widget
// reads.
Column {
    id: opts

    property string widget: ""

    readonly property string path: "background.widgets.imageConverter"

    width: parent ? parent.width : 0
    spacing: Theme.s1

    function g(key, fallback) { return Inir.Config.getNestedValue(opts.path + "." + key, fallback); }
    function put(key, value) { Inir.Config.setNestedValue(opts.path + "." + key, value); }
    function cycle(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length]; }

    readonly property var _formats: ["png", "jpg", "webp", "avif", "bmp", "tiff", "pdf"]

    // ── Conversion ───────────────────────────────────────────
    MenuSection { label: I18n.tr("Conversion"); gloss: "変換" }
    MenuRow {
        label: I18n.tr("Output format")
        value: String(opts.g("selectedFormat", "webp")).toUpperCase()
        closeOnTrigger: false
        onTriggered: opts.put("selectedFormat", opts.cycle(opts._formats, String(opts.g("selectedFormat", "webp"))))
    }
    MenuRow {
        // Not an action -- a hint row, so the panel states how the widget is fed.
        label: I18n.tr("Drop images on the widget to convert")
        closeOnTrigger: false
    }
}
