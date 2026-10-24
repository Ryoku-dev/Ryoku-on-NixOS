pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir

// Right-click options for the vendored iRiS "Custom image" canvas widget. Every
// control writes the widget's own inir config on the daemon's single settings
// path (inir.background.widgets.customImage.*), the store the widget reads, so
// the frame re-renders live. Custom image carries no preset logic, so each value
// is a plain write.
Column {
    id: opts

    property string widget: ""

    readonly property string path: "background.widgets.customImage"

    width: parent ? parent.width : 0
    spacing: Theme.s1

    function g(key, fallback) { return Inir.Config.getNestedValue(opts.path + "." + key, fallback); }
    function put(key, value) { Inir.Config.setNestedValue(opts.path + "." + key, value); }
    function cap(s) { return (s && s.length > 0) ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
    function cycle(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length]; }

    readonly property string sourceMode: opts.g("sourceMode", "file") === "folder" ? "folder" : "file"

    // The full iRiS shape ladder, cycled in place; a name reads fuller than a
    // clipped swatch grid inside the menu card.
    readonly property var _shapes: [
        "Circle", "Square", "Slanted", "Arch", "Fan", "Arrow", "SemiCircle", "Oval",
        "Pill", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny",
        "VerySunny", "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided",
        "Cookie12Sided", "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst",
        "Boom", "SoftBoom", "Flower", "Puffy", "PuffyDiamond", "PixelCircle",
        "PixelTriangle", "Bun", "Heart"
    ]
    function shapeLabel(v) { return String(v).replace(/([A-Z])/g, " $1").replace(/([0-9]+)/g, " $1").replace(/\s+/g, " ").trim(); }

    // ── Source ───────────────────────────────────────────────
    MenuSection { label: I18n.tr("Source"); gloss: "素材" }
    MenuRow {
        label: I18n.tr("Source type")
        value: opts.sourceMode === "folder" ? I18n.tr("Folder gallery") : I18n.tr("Single file")
        closeOnTrigger: false
        onTriggered: opts.put("sourceMode", opts.sourceMode === "folder" ? "file" : "folder")
    }
    MenuTextField {
        visible: opts.sourceMode === "file"
        label: I18n.tr("Media file")
        placeholder: I18n.tr("Image, GIF, or video path")
        text: String(opts.g("path", ""))
        onCommitted: (v) => opts.put("path", v.trim())
    }
    MenuTextField {
        visible: opts.sourceMode === "folder"
        label: I18n.tr("Media folder")
        placeholder: I18n.tr("Folder of images or videos")
        text: String(opts.g("folder", ""))
        onCommitted: (v) => opts.put("folder", v.trim())
    }
    MenuRow {
        visible: opts.sourceMode === "folder"
        label: I18n.tr("Media type")
        value: opts.cap(String(opts.g("mediaFilter", "all")))
        closeOnTrigger: false
        onTriggered: opts.put("mediaFilter", opts.cycle(["all", "images", "gifs", "videos"], String(opts.g("mediaFilter", "all"))))
    }

    // ── Gallery rotation (folder mode) ───────────────────────
    MenuSection { visible: opts.sourceMode === "folder"; label: I18n.tr("Rotation"); gloss: "巡回" }
    MenuRow {
        visible: opts.sourceMode === "folder"
        label: I18n.tr("Order")
        value: opts.g("order", "sequential") === "random" ? I18n.tr("Random") : I18n.tr("Sequential")
        closeOnTrigger: false
        onTriggered: opts.put("order", opts.g("order", "sequential") === "random" ? "sequential" : "random")
    }
    MenuSlider {
        id: intervalSlider
        visible: opts.sourceMode === "folder"
        label: I18n.tr("Change every")
        from: 3; to: 3600; step: 5
        value: Number(opts.g("intervalSeconds", 30))
        valueText: Math.round(intervalSlider.value) + "s"
        onMoved: (v) => opts.put("intervalSeconds", Math.round(v))
        onReleased: (v) => opts.put("intervalSeconds", Math.round(v))
    }

    // ── Shape ────────────────────────────────────────────────
    MenuSection { label: I18n.tr("Shape"); gloss: "形状" }
    MenuRow {
        label: I18n.tr("Shape")
        value: opts.shapeLabel(opts.g("shape", "Cookie4Sided"))
        closeOnTrigger: false
        onTriggered: opts.put("shape", opts.cycle(opts._shapes, String(opts.g("shape", "Cookie4Sided"))))
    }

    // ── Layout ───────────────────────────────────────────────
    MenuSection { label: I18n.tr("Layout"); gloss: "配置" }
    MenuSlider {
        id: sizeSlider
        label: I18n.tr("Size")
        from: 80; to: 1200; step: 10
        value: Number(opts.g("size", 220))
        valueText: Math.round(sizeSlider.value)
        onMoved: (v) => opts.put("size", Math.round(v))
        onReleased: (v) => opts.put("size", Math.round(v))
    }
    MenuRow {
        label: I18n.tr("Fit")
        value: opts.g("fitMode", "cover") === "contain" ? I18n.tr("Show full media") : I18n.tr("Crop to fill")
        closeOnTrigger: false
        onTriggered: opts.put("fitMode", opts.g("fitMode", "cover") === "contain" ? "cover" : "contain")
    }
    MenuSlider {
        id: transSlider
        label: I18n.tr("Transition")
        from: 0; to: 2000; step: 50
        value: Number(opts.g("transitionDuration", 450))
        valueText: Math.round(transSlider.value) + "ms"
        onMoved: (v) => opts.put("transitionDuration", Math.round(v))
        onReleased: (v) => opts.put("transitionDuration", Math.round(v))
    }
}
