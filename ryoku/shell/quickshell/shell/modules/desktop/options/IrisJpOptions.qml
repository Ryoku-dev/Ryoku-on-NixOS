pragma ComponentBehavior: Bound
import QtQuick
import ".."
import "../Singletons"
import Ryoku.Ui.Singletons
import inir.modules.common as Inir
import inir.modules.background.widgets.japaneseTypography as Jp

// Right-click options for the vendored iRiS "Japanese type" canvas widget, in
// Ryoku's menu idiom. Every control writes the widget's own inir config on the
// daemon's single settings path (inir.background.widgets.japaneseTypography.*),
// the same store the widget reads, so the poster re-renders live. Composition,
// palette and font presets apply through the upstream preset logic
// (JapaneseTypographyPresets.js); a single value flips its group's preset to
// "custom", exactly as the iNiR settings page does.
Column {
    id: opts

    // The Ryoku widget key the loader mounts this for (unused: the inir path is
    // fixed for this widget, but kept so every options panel shares one API).
    property string widget: ""

    readonly property string path: "background.widgets.japaneseTypography"

    width: parent ? parent.width : 0
    spacing: Theme.s1

    // ── config helpers (all reactive through the inir Config revision) ──
    function g(key, fallback) { return Inir.Config.getNestedValue(opts.path + "." + key, fallback); }
    function put(key, value) { Inir.Config.setNestedValue(opts.path + "." + key, value); }
    function setV(key, value, group) { Inir.Config.setNestedValues(Jp.JapaneseTypographyPresets.setValue(opts.path, key, value, group)); }
    function applyComposition(preset) { Inir.Config.setNestedValues(Jp.JapaneseTypographyPresets.composition(opts.path, preset)); }
    function applyPalette(preset) { Inir.Config.setNestedValues(Jp.JapaneseTypographyPresets.palette(opts.path, preset)); }
    function applyFont(preset) { Inir.Config.setNestedValues(Jp.JapaneseTypographyPresets.font(opts.path, preset)); }
    function cap(s) { return (s && s.length > 0) ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
    function cycle(list, cur) { const i = list.indexOf(cur); return list[(i + 1) % list.length]; }
    function famLabel(v, sameLabel) {
        if (v === "" || v === undefined || v === null) return sameLabel;
        if (v === "serif") return "Serif";
        if (v === "sans-serif") return "Sans";
        if (v === "monospace") return "Mono";
        return opts.cap(String(v));
    }

    readonly property string paletteMode: String(opts.g("paletteMode", "adaptive"))
    readonly property bool manual: opts.paletteMode === "manual"
    readonly property real outlineOpacity: Number(opts.g("outlineOpacity", 0))

    readonly property var _paletteRoles: [
        { key: "primaryColor",   label: I18n.tr("Lead title"),   fallback: "#E7D4B2" },
        { key: "secondaryColor", label: I18n.tr("Secondary"),    fallback: "#CDB48D" },
        { key: "sealColor",      label: I18n.tr("Seal"),         fallback: "#A64B39" },
        { key: "detailColor",    label: I18n.tr("Footer & date"), fallback: "#D0B996" },
        { key: "ruleColor",      label: I18n.tr("Rule"),         fallback: "#C18A53" }
    ]

    // ── Content ──────────────────────────────────────────────
    MenuSection { label: I18n.tr("Content"); gloss: "内容" }
    MenuTextField {
        label: I18n.tr("Lead title")
        placeholder: I18n.tr("Lead title")
        text: String(opts.g("primaryText", "夏の記憶"))
        onCommitted: (v) => opts.put("primaryText", v)
    }
    MenuTextField {
        label: I18n.tr("Secondary copy")
        placeholder: I18n.tr("Secondary vertical copy")
        text: String(opts.g("secondaryText", "潮風と、あの子と、終わらない夏"))
        onCommitted: (v) => opts.put("secondaryText", v)
    }
    MenuTextField {
        label: I18n.tr("Seal")
        placeholder: I18n.tr("Seal text")
        text: String(opts.g("sealText", "特別展"))
        onCommitted: (v) => opts.put("sealText", v)
    }
    MenuTextField {
        label: I18n.tr("Footer")
        placeholder: I18n.tr("Footer label")
        text: String(opts.g("footerText", "PACIFIC DRIVE-IN"))
        onCommitted: (v) => opts.put("footerText", v)
    }
    MenuTextField {
        label: I18n.tr("Date line")
        placeholder: I18n.tr("Date or edition line")
        text: String(opts.g("dateText", "7.12 — 8.31"))
        onCommitted: (v) => opts.put("dateText", v)
    }

    // ── Layout ───────────────────────────────────────────────
    MenuSection { label: I18n.tr("Layout"); gloss: "構成" }
    MenuRow {
        label: I18n.tr("Preset")
        value: opts.cap(String(opts.g("preset", "exhibition")))
        closeOnTrigger: false
        onTriggered: opts.applyComposition(opts.cycle(["exhibition", "magazine", "minimal", "traditional"], String(opts.g("preset", "exhibition"))))
    }
    MenuRow {
        label: I18n.tr("Mirror composition")
        value: opts.g("mirrorLayout", false) ? "On" : "Off"
        on: opts.g("mirrorLayout", false)
        closeOnTrigger: false
        onTriggered: opts.setV("mirrorLayout", !opts.g("mirrorLayout", false), "composition")
    }
    MenuRow {
        label: I18n.tr("Rotate Latin")
        value: opts.g("rotateLatin", false) ? "On" : "Off"
        on: opts.g("rotateLatin", false)
        closeOnTrigger: false
        onTriggered: opts.setV("rotateLatin", !opts.g("rotateLatin", false), "composition")
    }
    MenuSlider {
        id: cwSlider
        label: I18n.tr("Content width")
        from: 240; to: 720; step: 10
        value: Number(opts.g("contentWidth", 330))
        valueText: Math.round(cwSlider.value)
        onMoved: (v) => opts.setV("contentWidth", Math.round(v), "composition")
        onReleased: (v) => opts.setV("contentWidth", Math.round(v), "composition")
    }
    MenuSlider {
        id: chSlider
        label: I18n.tr("Content height")
        from: 320; to: 900; step: 10
        value: Number(opts.g("contentHeight", 600))
        valueText: Math.round(chSlider.value)
        onMoved: (v) => opts.setV("contentHeight", Math.round(v), "composition")
        onReleased: (v) => opts.setV("contentHeight", Math.round(v), "composition")
    }

    // ── Elements ─────────────────────────────────────────────
    MenuSection { label: I18n.tr("Elements"); gloss: "表示" }
    MenuRow {
        label: I18n.tr("Secondary copy")
        value: opts.g("showSecondary", true) ? "On" : "Off"
        on: opts.g("showSecondary", true)
        closeOnTrigger: false
        onTriggered: opts.setV("showSecondary", !opts.g("showSecondary", true), "composition")
    }
    MenuRow {
        label: I18n.tr("Exhibition seal")
        value: opts.g("showSeal", true) ? "On" : "Off"
        on: opts.g("showSeal", true)
        closeOnTrigger: false
        onTriggered: opts.setV("showSeal", !opts.g("showSeal", true), "composition")
    }
    MenuRow {
        label: I18n.tr("Footer and date")
        value: opts.g("showFooter", true) ? "On" : "Off"
        on: opts.g("showFooter", true)
        closeOnTrigger: false
        onTriggered: opts.setV("showFooter", !opts.g("showFooter", true), "composition")
    }
    MenuRow {
        label: I18n.tr("Editorial rule")
        value: opts.g("showRule", true) ? "On" : "Off"
        on: opts.g("showRule", true)
        closeOnTrigger: false
        onTriggered: opts.setV("showRule", !opts.g("showRule", true), "composition")
    }

    // ── Type ─────────────────────────────────────────────────
    MenuSection { label: I18n.tr("Type"); gloss: "書体" }
    MenuRow {
        label: I18n.tr("Direction")
        value: opts.cap(String(opts.g("fontPreset", "mincho")))
        closeOnTrigger: false
        onTriggered: opts.applyFont(opts.cycle(["mincho", "mixed", "gothic"], String(opts.g("fontPreset", "mincho"))))
    }
    MenuRow {
        label: I18n.tr("Lead font")
        value: opts.famLabel(String(opts.g("fontFamily", "serif")), I18n.tr("Serif"))
        closeOnTrigger: false
        onTriggered: opts.setV("fontFamily", opts.cycle(["serif", "sans-serif", "monospace"], String(opts.g("fontFamily", "serif"))), "font")
    }
    MenuRow {
        label: I18n.tr("Secondary font")
        value: opts.famLabel(String(opts.g("secondaryFontFamily", "")), I18n.tr("Same as title"))
        closeOnTrigger: false
        onTriggered: opts.setV("secondaryFontFamily", opts.cycle(["", "serif", "sans-serif", "monospace"], String(opts.g("secondaryFontFamily", ""))), "font")
    }
    MenuRow {
        label: I18n.tr("Footer font")
        value: opts.famLabel(String(opts.g("latinFontFamily", "")), I18n.tr("Interface"))
        closeOnTrigger: false
        onTriggered: opts.setV("latinFontFamily", opts.cycle(["", "serif", "sans-serif", "monospace"], String(opts.g("latinFontFamily", ""))), "font")
    }
    MenuSlider {
        id: pwSlider
        label: I18n.tr("Lead weight")
        from: 100; to: 900; step: 100
        value: Number(opts.g("primaryWeight", 500))
        valueText: Math.round(pwSlider.value)
        onMoved: (v) => opts.setV("primaryWeight", Math.round(v), "font")
        onReleased: (v) => opts.setV("primaryWeight", Math.round(v), "font")
    }
    MenuSlider {
        id: swSlider
        label: I18n.tr("Secondary weight")
        from: 100; to: 900; step: 100
        value: Number(opts.g("secondaryWeight", 400))
        valueText: Math.round(swSlider.value)
        onMoved: (v) => opts.setV("secondaryWeight", Math.round(v), "font")
        onReleased: (v) => opts.setV("secondaryWeight", Math.round(v), "font")
    }
    MenuSlider {
        id: fwSlider
        label: I18n.tr("Footer weight")
        from: 100; to: 900; step: 100
        value: Number(opts.g("latinWeight", 600))
        valueText: Math.round(fwSlider.value)
        onMoved: (v) => opts.setV("latinWeight", Math.round(v), "font")
        onReleased: (v) => opts.setV("latinWeight", Math.round(v), "font")
    }
    MenuSlider {
        id: psSlider
        label: I18n.tr("Lead size")
        from: 28; to: 140; step: 2
        value: Number(opts.g("primarySize", 72))
        valueText: Math.round(psSlider.value)
        onMoved: (v) => opts.setV("primarySize", Math.round(v), "composition")
        onReleased: (v) => opts.setV("primarySize", Math.round(v), "composition")
    }
    MenuSlider {
        id: ssSlider
        label: I18n.tr("Secondary size")
        from: 10; to: 48; step: 1
        value: Number(opts.g("secondarySize", 18))
        valueText: Math.round(ssSlider.value)
        onMoved: (v) => opts.setV("secondarySize", Math.round(v), "composition")
        onReleased: (v) => opts.setV("secondarySize", Math.round(v), "composition")
    }
    MenuSlider {
        id: fsSlider
        label: I18n.tr("Footer size")
        from: 8; to: 32; step: 1
        value: Number(opts.g("footerSize", 14))
        valueText: Math.round(fsSlider.value)
        onMoved: (v) => opts.setV("footerSize", Math.round(v), "composition")
        onReleased: (v) => opts.setV("footerSize", Math.round(v), "composition")
    }
    MenuSlider {
        id: dsSlider
        label: I18n.tr("Date size")
        from: 8; to: 28; step: 1
        value: Number(opts.g("dateSize", 12))
        valueText: Math.round(dsSlider.value)
        onMoved: (v) => opts.setV("dateSize", Math.round(v), "composition")
        onReleased: (v) => opts.setV("dateSize", Math.round(v), "composition")
    }
    MenuSlider {
        id: pcSlider
        label: I18n.tr("Lead columns")
        from: 1; to: 4; step: 1
        value: Number(opts.g("primaryColumns", 2))
        valueText: Math.round(pcSlider.value)
        onMoved: (v) => opts.setV("primaryColumns", Math.round(v), "composition")
        onReleased: (v) => opts.setV("primaryColumns", Math.round(v), "composition")
    }
    MenuSlider {
        id: scSlider
        label: I18n.tr("Secondary columns")
        from: 1; to: 5; step: 1
        value: Number(opts.g("secondaryColumns", 2))
        valueText: Math.round(scSlider.value)
        onMoved: (v) => opts.setV("secondaryColumns", Math.round(v), "composition")
        onReleased: (v) => opts.setV("secondaryColumns", Math.round(v), "composition")
    }
    MenuSlider {
        id: gapSlider
        label: I18n.tr("Column gap")
        from: 4; to: 48; step: 1
        value: Number(opts.g("columnGap", 14))
        valueText: Math.round(gapSlider.value)
        onMoved: (v) => opts.setV("columnGap", Math.round(v), "composition")
        onReleased: (v) => opts.setV("columnGap", Math.round(v), "composition")
    }
    MenuSlider {
        id: lsSlider
        label: I18n.tr("Lead spacing")
        from: 0; to: 20; step: 1
        value: Number(opts.g("letterSpacing", 2))
        valueText: Math.round(lsSlider.value)
        onMoved: (v) => opts.setV("letterSpacing", Math.round(v), "font")
        onReleased: (v) => opts.setV("letterSpacing", Math.round(v), "font")
    }
    MenuSlider {
        id: slsSlider
        label: I18n.tr("Secondary spacing")
        from: 0; to: 20; step: 1
        value: Number(opts.g("secondaryLetterSpacing", 1))
        valueText: Math.round(slsSlider.value)
        onMoved: (v) => opts.setV("secondaryLetterSpacing", Math.round(v), "font")
        onReleased: (v) => opts.setV("secondaryLetterSpacing", Math.round(v), "font")
    }

    // ── Colour ───────────────────────────────────────────────
    MenuSection { label: I18n.tr("Colour"); gloss: "彩色" }
    MenuRow {
        label: I18n.tr("Palette")
        value: opts.cap(String(opts.g("palettePreset", "adaptive")))
        closeOnTrigger: false
        onTriggered: opts.applyPalette(opts.cycle(["adaptive", "sumi", "ivory", "sunset", "cinema"], String(opts.g("palettePreset", "adaptive"))))
    }
    MenuRow {
        label: I18n.tr("Colour source")
        value: opts.manual ? I18n.tr("Manual") : I18n.tr("Adaptive")
        on: opts.manual
        closeOnTrigger: false
        onTriggered: opts.manual ? opts.applyPalette("adaptive") : opts.setV("paletteMode", "manual", "palette")
    }
    MenuInkPicker {
        visible: opts.manual
        roles: opts._paletteRoles
        readColor: (k, fb) => String(opts.g(k, fb))
        writeColor: (k, hex) => opts.setV(k, hex, "palette")
    }
    MenuSlider {
        id: poSlider
        label: I18n.tr("Lead opacity")
        from: 10; to: 100; step: 5
        value: Number(opts.g("primaryOpacity", 100))
        valueText: Math.round(poSlider.value) + "%"
        onMoved: (v) => opts.setV("primaryOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("primaryOpacity", Math.round(v), "palette")
    }
    MenuSlider {
        id: soSlider
        label: I18n.tr("Secondary opacity")
        from: 10; to: 100; step: 5
        value: Number(opts.g("secondaryOpacity", 78))
        valueText: Math.round(soSlider.value) + "%"
        onMoved: (v) => opts.setV("secondaryOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("secondaryOpacity", Math.round(v), "palette")
    }
    MenuSlider {
        id: sealoSlider
        label: I18n.tr("Seal opacity")
        from: 10; to: 100; step: 5
        value: Number(opts.g("sealOpacity", 100))
        valueText: Math.round(sealoSlider.value) + "%"
        onMoved: (v) => opts.setV("sealOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("sealOpacity", Math.round(v), "palette")
    }
    MenuSlider {
        id: detoSlider
        label: I18n.tr("Detail opacity")
        from: 10; to: 100; step: 5
        value: Number(opts.g("detailOpacity", 72))
        valueText: Math.round(detoSlider.value) + "%"
        onMoved: (v) => opts.setV("detailOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("detailOpacity", Math.round(v), "palette")
    }
    MenuSlider {
        id: ruleoSlider
        label: I18n.tr("Rule opacity")
        from: 10; to: 100; step: 5
        value: Number(opts.g("ruleOpacity", 78))
        valueText: Math.round(ruleoSlider.value) + "%"
        onMoved: (v) => opts.setV("ruleOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("ruleOpacity", Math.round(v), "palette")
    }
    MenuSlider {
        id: ruletSlider
        label: I18n.tr("Rule thickness")
        from: 1; to: 6; step: 1
        value: Number(opts.g("ruleThickness", 1))
        valueText: Math.round(ruletSlider.value)
        onMoved: (v) => opts.setV("ruleThickness", Math.round(v), "composition")
        onReleased: (v) => opts.setV("ruleThickness", Math.round(v), "composition")
    }
    MenuSlider {
        id: sealfSlider
        label: I18n.tr("Seal fill")
        from: 0; to: 100; step: 5
        value: Number(opts.g("sealFillOpacity", 0))
        valueText: Math.round(sealfSlider.value) + "%"
        onMoved: (v) => opts.setV("sealFillOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("sealFillOpacity", Math.round(v), "palette")
    }

    // ── Legibility ───────────────────────────────────────────
    MenuSection { label: I18n.tr("Legibility"); gloss: "可読" }
    MenuSlider {
        id: shadowSlider
        label: I18n.tr("Wallpaper shadow")
        from: 0; to: 100; step: 5
        value: Number(opts.g("shadowStrength", 35))
        valueText: Math.round(shadowSlider.value) + "%"
        onMoved: (v) => opts.setV("shadowStrength", Math.round(v), "palette")
        onReleased: (v) => opts.setV("shadowStrength", Math.round(v), "palette")
    }
    MenuSlider {
        id: outlineSlider
        label: I18n.tr("Text outline")
        from: 0; to: 100; step: 5
        value: Number(opts.g("outlineOpacity", 0))
        valueText: Math.round(outlineSlider.value) + "%"
        onMoved: (v) => opts.setV("outlineOpacity", Math.round(v), "palette")
        onReleased: (v) => opts.setV("outlineOpacity", Math.round(v), "palette")
    }
    MenuInkPicker {
        visible: opts.outlineOpacity > 0
        roles: [{ key: "outlineColor", label: I18n.tr("Outline colour"), fallback: "#000000" }]
        readColor: (k, fb) => String(opts.g(k, fb))
        writeColor: (k, hex) => opts.setV(k, hex, "palette")
    }
}
