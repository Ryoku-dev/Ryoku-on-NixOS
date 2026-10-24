// Karuma's configuration schema: defaults, validation and the small edit
// operations the hub performs. Pure data in, pure data out (no Quickshell), so
// it is unit-tested with node (KarumaSchema.test.mjs) and shared by the bar
// (through KarumaPalette) and the hub (through KarumaConfig).
//
// All settings live in the bar style's one configuration file,
// ~/.config/karuma/style.json. Existing keys (hours, height, typeSize, indicators,
// motion, sealGlyph and monoFont) keep their meaning; Karuma adds opacity, floating,
// shape, gap, modules, scale, showClock, showDate, dateFormat, indicator,
// workspaceStyle and quick. The hub edits `hours` (12/24-hour) and `motion`
// (the Animations switch: "paper" is on, "still" is off) through the same file.
// Karuma keeps the explicit three-lane model, adds four-edge geometry, native rails,
// per-module geometry, progress placement and behaviour controls; old clock-pivot
// `modules.order` files still migrate on read. Unknown keys are carried
// through untouched when the configuration is saved.

var SHAPES = ["square", "rounded", "pill"];
var LAYOUTS = ["strip", "islands"];
var EDGES = ["top", "bottom", "left", "right"];
var SIDES = EDGES;
var ALIGNS = ["start", "center", "end"];
var PROGRESS_STYLES = ["none", "hairline", "track", "fill", "accent"];
var PROGRESS_PLACEMENTS = ["auto", "module", "left", "center", "right", "whole"];
var FULLSCREEN_MODES = ["hide", "show"];
var SCALE_MIN = 0.65;
var SCALE_MAX = 1.8;

// Built-in modules. Karuma stores placement as three explicit lanes instead
// of using the clock as a pivot. The seal (the hub button) stays the one fixed
// brand anchor at the start of the left lane; everything below is movable.
var MODULES = [
    { id: "workspaces", label: "Workspaces", desc: "Your workspaces, drawn in the style chosen under Appearance.", kana: "頁" },
    { id: "title", label: "Window title", desc: "The focused app and its title.", kana: "窓" },
    { id: "clock", label: "Clock", desc: "Time and date. It can live in any lane like every other module.", kana: "時" },
    { id: "media", label: "Now playing", desc: "The song, its underline the progress.", kana: "楽" },
    { id: "tray", label: "App tray", desc: "The arrow that reveals the apps running in the background.", kana: "駐" },
    { id: "status", label: "Status", desc: "Network, Bluetooth, volume, brightness, battery.", kana: "音" },
    { id: "indicators", label: "Indicators", desc: "Recording and stay-awake stamps.", kana: "印" },
    { id: "notifications", label: "Notifications", desc: "Stamps for waiting notifications.", kana: "報" },
    { id: "quick", label: "Quick settings", desc: "The 設 button that opens the quick settings menu.", kana: "設" }
];

// What the quick settings menu can offer. A control with no hardware behind it
// (brightness on a desktop, Bluetooth with no adapter) is left out of the menu
// on its own; this list is only what the user chose to hide.
var QUICK = [
    { id: "volume", label: "Volume", desc: "Output level and mute.", kana: "音" },
    { id: "brightness", label: "Brightness", desc: "Screen backlight. Laptops and other backlit panels only.", kana: "光" },
    { id: "wifi", label: "Wi-Fi", desc: "Switch the wireless radio on or off.", kana: "網" },
    { id: "bluetooth", label: "Bluetooth", desc: "Switch the adapter on or off.", kana: "双" },
    { id: "mic", label: "Microphone", desc: "Mute or unmute the default input.", kana: "声" },
    { id: "awake", label: "Stay awake", desc: "Keep the machine from idling or sleeping.", kana: "目" }
];

var QUICK_IDS = QUICK.map(function (q) { return q.id; });

// How the workspaces are drawn. "kanji" is the shipped look and the default.
// `sample` is what the hub previews (three marks, the middle one live).
var WORKSPACE_STYLES = [
    { id: "kanji", label: "Kanji", desc: "Ink numerals on a sliding plate." },
    { id: "numbers", label: "Numbers", desc: "Plain 1 2 3 on the same plate." },
    { id: "roman", label: "Roman", desc: "Serif numerals, Ⅰ Ⅱ Ⅲ." },
    { id: "dashes", label: "Dashes", desc: "Minimal bars; the live one stretches." },
    { id: "dots", label: "Dots", desc: "Compact pips; the live one is solid." }
];
var WORKSPACE_STYLE_IDS = WORKSPACE_STYLES.map(function (w) { return w.id; });
var DEFAULT_WORKSPACE_STYLE = "kanji";

var ROMAN = ["", "Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ"];

function normalizeWorkspaceStyle(value) {
    var v = String(value);
    return WORKSPACE_STYLE_IDS.indexOf(v) >= 0 ? v : DEFAULT_WORKSPACE_STYLE;
}

// The text a workspace shows in a given style. `kanji` is the label the shell
// already worked out for it (kanji numeral for 1-10, else the name's first two
// characters). Named or out-of-range workspaces fall back to that label in every
// text style, so nothing ever draws blank. Dashes and dots draw no text.
function workspaceText(style, id, kanji) {
    var s = normalizeWorkspaceStyle(style);
    var n = parseInt(String(id), 10);
    var numeric = !isNaN(n) && String(n) === String(id).trim() && n >= 1;
    if (s === "numbers") return numeric ? String(n) : String(kanji);
    if (s === "roman") return numeric && n < ROMAN.length ? ROMAN[n] : (numeric ? String(n) : String(kanji));
    if (s === "dashes" || s === "dots") return "";
    return String(kanji);
}

// The line under the bar.
var INDICATORS = ["disabled", "daily", "music"];

// Date formats are Qt patterns (Qt.formatDate). A "|" splits the date into
// the two stacked lines the clock shows; without one it is a single line.
var DEFAULT_DATE = "ddd|dd MMM";
var DATE_PRESETS = ["ddd|dd MMM", "ddd dd MMM", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "dddd|d MMMM"];
var DATE_MAX = 32;

var PRESETS = [
    { id: "default", label: "Default", desc: "The original Karuma look on the current feature set." },
    { id: "minimal", label: "Minimal", desc: "Workspaces, clock, status and quick settings only." },
    { id: "media", label: "Media", desc: "Now playing shares centre stage with the clock." },
    { id: "dense", label: "Dense", desc: "A compact continuous strip for small displays." },
    { id: "rail", label: "Rail", desc: "A vertical right-edge rail with compact native modules." }
];


var DEFAULT_ORDER = MODULES.map(function (m) { return m.id; });
var LANES = ["left", "center", "right"];
var MODULE_STYLES = ["plain", "paper", "outline", "accent", "ghost"];
var DEFAULT_LANES = {
    left: ["workspaces", "title"],
    center: ["clock"],
    right: ["media", "tray", "status", "indicators", "notifications", "quick"]
};

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v); }

function num(v, lo, hi, fallback) {
    var n = Number(v);
    if (v === null || v === undefined || v === "" || !isFinite(n)) return fallback;
    return Math.max(lo, Math.min(hi, n));
}

function moduleKnown(id) { return DEFAULT_ORDER.indexOf(id) >= 0; }
function isPluginRef(id) {
    return /^ryoku:[a-z0-9][a-z0-9-]*$/.test(String(id))
        || /^omarchy:[a-z0-9][a-z0-9._-]*$/.test(String(id));
}
function moduleRefValid(id) { return moduleKnown(String(id)) || isPluginRef(String(id)); }

// Where a built-in that an older config predates belongs in `rows`: straight
// after its nearest shipped predecessor, else before its nearest shipped
// successor, else at the end. Nothing the user arranged is moved.
var SLOTTED_BUILTINS = ["tray"];

function slotFor(rows, shipped, index) {
    // Built-ins that predate this rule keep their historical "append" behaviour.
    if (SLOTTED_BUILTINS.indexOf(shipped[index]) < 0) return rows.length;
    for (var p = index - 1; p >= 0; --p) {
        var before = rows.indexOf(shipped[p]);
        if (before >= 0) return before + 1;
    }
    for (var n = index + 1; n < shipped.length; ++n) {
        var after = rows.indexOf(shipped[n]);
        if (after >= 0) return after;
    }
    return rows.length;
}

function copyLanes(value) {
    var out = { left: [], center: [], right: [] };
    if (!isObject(value)) return out;
    for (var i = 0; i < LANES.length; ++i) {
        var lane = LANES[i];
        out[lane] = Array.isArray(value[lane]) ? value[lane].slice() : [];
    }
    return out;
}

// Older Karuma builds stored one order list with the clock acting as a pivot.
// Convert that shape once on read so existing users keep exactly the arrangement
// they had when the three-lane layout replaces the clock-pivot model.
function lanesFromLegacyOrder(value) {
    var order = normalizeOrder(value);
    var at = order.indexOf("clock");
    if (at < 0) at = Math.min(2, order.length);
    return {
        left: order.slice(0, at).filter(function (id) { return id !== "clock"; }),
        center: ["clock"],
        right: order.slice(at + 1).filter(function (id) { return id !== "clock"; })
    };
}

// Every built-in exists exactly once. Plugin references are preserved while they
// are installed or absent, so temporarily disabling a plugin never destroys the
// user's chosen lane/order. Unknown junk and duplicates are dropped.
function normalizeLanes(value, legacyOrder) {
    var src = isObject(value) ? copyLanes(value) : lanesFromLegacyOrder(legacyOrder);
    var out = { left: [], center: [], right: [] };
    var seen = [];
    for (var i = 0; i < LANES.length; ++i) {
        var lane = LANES[i];
        var rows = src[lane];
        for (var j = 0; j < rows.length; ++j) {
            var id = String(rows[j]);
            if (!moduleRefValid(id) || seen.indexOf(id) >= 0) continue;
            out[lane].push(id);
            seen.push(id);
        }
    }
    // A configuration written before a new built-in existed gains it in its
    // shipped lane without disturbing anything the user already arranged.
    for (var k = 0; k < LANES.length; ++k) {
        var target = LANES[k];
        var defs = DEFAULT_LANES[target];
        for (var m = 0; m < defs.length; ++m) {
            var builtin = defs[m];
            if (seen.indexOf(builtin) < 0) {
                out[target].splice(slotFor(out[target], defs, m), 0, builtin);
                seen.push(builtin);
            }
        }
    }
    return out;
}

function flattenLanes(lanes) {
    var l = normalizeLanes(lanes, DEFAULT_ORDER);
    return l.left.concat(l.center, l.right);
}

// Compatibility helper for old callers/tests: a damaged legacy list is repaired
// in shipped order. New code should use normalizeLanes.
function normalizeOrder(value) {
    var out = [];
    var src = Array.isArray(value) ? value : [];
    for (var i = 0; i < src.length; ++i) {
        var id = String(src[i]);
        if (moduleKnown(id) && out.indexOf(id) < 0) out.push(id);
    }
    for (var j = 0; j < DEFAULT_ORDER.length; ++j) {
        if (out.indexOf(DEFAULT_ORDER[j]) >= 0) continue;
        // A built-in this list predates slots in before its next shipped neighbour.
        out.splice(slotFor(out, DEFAULT_ORDER, j), 0, DEFAULT_ORDER[j]);
    }
    return out;
}

function normalizeHidden(value) {
    var out = [];
    var src = Array.isArray(value) ? value : [];
    for (var i = 0; i < src.length; ++i) {
        var id = String(src[i]);
        if (moduleRefValid(id) && out.indexOf(id) < 0) out.push(id);
    }
    return out;
}

function normalizeModuleStyles(value) {
    var out = {};
    if (!isObject(value)) return out;
    for (var id in value) {
        if (!moduleRefValid(id)) continue;
        var style = String(value[id]);
        if (MODULE_STYLES.indexOf(style) >= 0 && style !== "plain") out[id] = style;
    }
    return out;
}

function normalizeModuleOptions(value) {
    var out = {};
    if (!isObject(value)) return out;
    for (var id in value) {
        if (!moduleRefValid(id) || !isObject(value[id])) continue;
        var src = value[id];
        var row = {
            scale: Math.round(num(src.scale, 0.6, 1.6, 1) * 100) / 100,
            padding: Math.round(num(src.padding, 0, 20, 0)),
            opacity: Math.round(num(src.opacity, 0.2, 1, 1) * 100) / 100
        };
        if (row.scale !== 1 || row.padding !== 0 || row.opacity !== 1) out[id] = row;
    }
    return out;
}

function normalizeQuick(value) {
    var out = [];
    var src = Array.isArray(value) ? value : [];
    for (var i = 0; i < src.length; ++i) {
        var id = String(src[i]);
        if (QUICK_IDS.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id);
    }
    return out;
}

// A date pattern as typed. Not trimmed (the hub's text field would fight the
// user over a trailing space), only capped, and an empty one is the default.
function normalizeDate(value) {
    if (typeof value !== "string" || value.trim() === "") return DEFAULT_DATE;
    return value.slice(0, DATE_MAX);
}

// The pattern as the clock draws it: { top, bottom }, bottom empty for a single line.
function splitDate(value) {
    var s = normalizeDate(value);
    var at = s.indexOf("|");
    if (at < 0) return { top: s, bottom: "" };
    var top = s.slice(0, at);
    var bottom = s.slice(at + 1).replace(/\|/g, " ");
    if (top.trim() === "") return { top: bottom, bottom: "" };
    if (bottom.trim() === "") return { top: top, bottom: "" };
    return { top: top, bottom: bottom };
}

function defaults() {
    return {
        opacity: 0.77,
        height: 38,
        layout: "strip",
        edge: "top",
        align: "center",
        length: 100,
        floating: true,
        shape: "rounded",
        cornerRadius: 12,
        innerRadiusBias: 0,
        borderWidth: 1,
        borderOpacity: 1,
        railWidth: 64,
        gap: { top: 4, bottom: 0, left: 24, right: 24 },
        lanes: copyLanes(DEFAULT_LANES),
        hidden: [],
        moduleStyles: {},
        moduleOptions: {},
        moduleGap: 14,
        islandPad: 8,
        islandGap: 16,
        laneSpread: 1,
        textScale: 1,
        iconScale: 1,
        scale: 0.95,
        animations: true,
        hours: "12h",
        showClock: true,
        showDate: true,
        dateFormat: DEFAULT_DATE,
        indicator: "daily",
        progressStyle: "track",
        progressPlacement: "auto",
        progressThickness: 2,
        progressOpacity: 0.9,
        fullscreenMode: "hide",
        reserveSpace: true,
        workspaceStyle: DEFAULT_WORKSPACE_STYLE,
        quickHidden: []
    };
}

// The Karuma part of a raw style object, always complete and in range.
function normalize(raw) {
    var r = isObject(raw) ? raw : {};
    var d = defaults();
    var g = isObject(r.gap) ? r.gap : {};
    var m = isObject(r.modules) ? r.modules : {};
    var q = isObject(r.quick) ? r.quick : {};
    var shape = String(r.shape);
    return {
        opacity: num(r.opacity, 0.05, 1, d.opacity),
        height: Math.round(num(r.height, 28, 80, d.height)),
        layout: LAYOUTS.indexOf(String(r.layout)) >= 0 ? String(r.layout) : d.layout,
        edge: EDGES.indexOf(String(r.edge)) >= 0 ? String(r.edge) : d.edge,
        align: ALIGNS.indexOf(String(r.align)) >= 0 ? String(r.align) : d.align,
        length: Math.round(num(r.length, 28, 100, d.length)),
        floating: r.floating === undefined ? d.floating : r.floating === true,
        shape: SHAPES.indexOf(shape) >= 0 ? shape : d.shape,
        cornerRadius: Math.round(num(r.cornerRadius, 0, 48, d.cornerRadius)),
        innerRadiusBias: Math.round(num(r.innerRadiusBias, -12, 12, d.innerRadiusBias)),
        borderWidth: Math.round(num(r.borderWidth, 0, 4, d.borderWidth) * 2) / 2,
        borderOpacity: Math.round(num(r.borderOpacity, 0, 1, d.borderOpacity) * 100) / 100,
        railWidth: Math.round(num(r.railWidth, 44, 128, d.railWidth)),
        gap: {
            top: Math.round(num(g.top, 0, 64, d.gap.top)),
            bottom: Math.round(num(g.bottom, 0, 64, d.gap.bottom)),
            left: Math.round(num(g.left, 0, 64, d.gap.left)),
            right: Math.round(num(g.right, 0, 64, d.gap.right))
        },
        lanes: normalizeLanes(m.lanes, m.order),
        hidden: normalizeHidden(m.hidden),
        moduleStyles: normalizeModuleStyles(m.styles),
        moduleOptions: normalizeModuleOptions(m.options),
        moduleGap: Math.round(num(r.moduleGap, 0, 40, d.moduleGap)),
        islandPad: Math.round(num(r.islandPad, 0, 28, d.islandPad)),
        islandGap: Math.round(num(r.islandGap, 0, 48, d.islandGap)),
        laneSpread: Math.round(num(r.laneSpread, 0, 1, d.laneSpread) * 100) / 100,
        textScale: Math.round(num(r.textScale, 0.65, 1.8, d.textScale) * 100) / 100,
        iconScale: Math.round(num(r.iconScale, 0.65, 1.8, d.iconScale) * 100) / 100,
        scale: Math.round(num(r.scale, SCALE_MIN, SCALE_MAX, d.scale) * 100) / 100,
        animations: String(r.motion) !== "still",
        hours: r.hours === "24h" ? "24h" : "12h",
        showClock: r.showClock !== false,
        showDate: r.showDate !== false,
        dateFormat: normalizeDate(r.dateFormat),
        indicator: INDICATORS.indexOf(String(r.indicator)) >= 0 ? String(r.indicator) : d.indicator,
        progressStyle: PROGRESS_STYLES.indexOf(String(r.progressStyle)) >= 0 ? String(r.progressStyle) : d.progressStyle,
        progressPlacement: PROGRESS_PLACEMENTS.indexOf(String(r.progressPlacement)) >= 0 ? String(r.progressPlacement) : d.progressPlacement,
        progressThickness: Math.round(num(r.progressThickness, 1, 8, d.progressThickness)),
        progressOpacity: Math.round(num(r.progressOpacity, 0.1, 1, d.progressOpacity) * 100) / 100,
        fullscreenMode: FULLSCREEN_MODES.indexOf(String(r.fullscreenMode)) >= 0 ? String(r.fullscreenMode) : d.fullscreenMode,
        reserveSpace: r.reserveSpace === undefined ? d.reserveSpace : r.reserveSpace === true,
        workspaceStyle: normalizeWorkspaceStyle(r.workspaceStyle),
        quickHidden: normalizeQuick(q.hidden)
    };
}

// ---------------------------------------------------------------- edits
// Each returns a new raw object; keys the schema does not own are preserved.

function copyRaw(raw) {
    var out = {};
    if (isObject(raw)) for (var k in raw) out[k] = raw[k];
    return out;
}

function withValue(raw, key, value) {
    var out = copyRaw(raw);
    out[key] = value;
    return out;
}

function withGap(raw, side, value) {
    if (SIDES.indexOf(side) < 0) return copyRaw(raw);
    var out = copyRaw(raw);
    var cur = normalize(raw).gap;
    var g = {};
    for (var i = 0; i < SIDES.length; ++i) g[SIDES[i]] = cur[SIDES[i]];
    g[side] = Math.round(num(value, 0, 64, cur[side]));
    out.gap = g;
    return out;
}

function withModules(raw, lanes, hidden, styles, options) {
    var out = copyRaw(raw);
    var current = isObject(raw) && isObject(raw.modules) ? raw.modules : {};
    var next = copyRaw(current);
    next.lanes = normalizeLanes(lanes, null);
    next.hidden = normalizeHidden(hidden);
    var currentConf = normalize(raw);
    next.styles = normalizeModuleStyles(styles === undefined ? currentConf.moduleStyles : styles);
    next.options = normalizeModuleOptions(options === undefined ? currentConf.moduleOptions : options);
    delete next.order;
    out.modules = next;
    return out;
}

function withHidden(raw, id, hide) {
    id = String(id);
    if (!moduleRefValid(id)) return copyRaw(raw);
    var c = normalize(raw);
    var hidden = c.hidden.filter(function (h) { return h !== id; });
    if (hide) hidden.push(id);
    return withModules(raw, c.lanes, hidden, c.moduleStyles, c.moduleOptions);
}

function laneOf(lanes, id) {
    for (var i = 0; i < LANES.length; ++i)
        if (lanes[LANES[i]].indexOf(id) >= 0) return LANES[i];
    return "";
}

function removeFromLanes(lanes, id) {
    var out = copyLanes(lanes);
    for (var i = 0; i < LANES.length; ++i) {
        var lane = LANES[i];
        out[lane] = out[lane].filter(function (x) { return x !== id; });
    }
    return out;
}

// Place a built-in or plugin in any lane at an explicit index. This is the one
// layout operation used by the hub, drag/drop and plugin auto-placement.
function withPlaced(raw, id, lane, to) {
    id = String(id); lane = String(lane);
    if (!moduleRefValid(id) || LANES.indexOf(lane) < 0) return copyRaw(raw);
    var c = normalize(raw);
    var lanes = removeFromLanes(c.lanes, id);
    var target = Number(to);
    if (!isFinite(target)) target = lanes[lane].length;
    target = Math.max(0, Math.min(lanes[lane].length, Math.round(target)));
    lanes[lane].splice(target, 0, id);
    return withModules(raw, lanes, c.hidden, c.moduleStyles, c.moduleOptions);
}

function withMoved(raw, id, to) {
    var c = normalize(raw);
    var lane = laneOf(c.lanes, String(id));
    if (!lane) return copyRaw(raw);
    return withPlaced(raw, id, lane, to);
}

function withModuleStyle(raw, id, style) {
    id = String(id); style = String(style);
    if (!moduleRefValid(id) || MODULE_STYLES.indexOf(style) < 0) return copyRaw(raw);
    var c = normalize(raw);
    var styles = {};
    for (var k in c.moduleStyles) styles[k] = c.moduleStyles[k];
    if (style === "plain") delete styles[id]; else styles[id] = style;
    return withModules(raw, c.lanes, c.hidden, styles, c.moduleOptions);
}

function moduleOptions(cfg, id) {
    var row = cfg && cfg.moduleOptions ? cfg.moduleOptions[String(id)] : null;
    return row || { scale: 1, padding: 0, opacity: 1 };
}

function withModuleOption(raw, id, key, value) {
    id = String(id); key = String(key);
    if (!moduleRefValid(id) || ["scale", "padding", "opacity"].indexOf(key) < 0) return copyRaw(raw);
    var c = normalize(raw);
    var options = {};
    for (var k in c.moduleOptions) {
        options[k] = { scale: c.moduleOptions[k].scale, padding: c.moduleOptions[k].padding, opacity: c.moduleOptions[k].opacity };
    }
    var row = moduleOptions(c, id);
    var next = { scale: row.scale, padding: row.padding, opacity: row.opacity };
    next[key] = value;
    options[id] = next;
    return withModules(raw, c.lanes, c.hidden, c.moduleStyles, options);
}

function withPreset(raw, id) {
    id = String(id);
    var out = copyRaw(raw);
    var currentConf = normalize(raw);
    var lanes = copyLanes(DEFAULT_LANES);
    var hidden = [];
    var styles = {};

    // Profiles reshape Karuma's built-ins, but a profile must never silently
    // delete a user's plugin placement, hidden state, or treatment. Keep plugin
    // refs in the lane where the user put them and merge them back after the
    // built-in recipe is chosen.
    var pluginLanes = { left: [], center: [], right: [] };
    for (var pi = 0; pi < LANES.length; ++pi) {
        var pl = LANES[pi];
        var rows = currentConf.lanes[pl] || [];
        for (var pj = 0; pj < rows.length; ++pj)
            if (isPluginRef(rows[pj])) pluginLanes[pl].push(rows[pj]);
    }
    for (var ph = 0; ph < currentConf.hidden.length; ++ph)
        if (isPluginRef(currentConf.hidden[ph])) hidden.push(currentConf.hidden[ph]);
    for (var ps in currentConf.moduleStyles)
        if (isPluginRef(ps)) styles[ps] = currentConf.moduleStyles[ps];

    if (id === "minimal") {
        hidden = hidden.concat(["title", "media", "tray", "indicators", "notifications"]);
        out.layout = "islands"; out.floating = true; out.scale = 0.92; out.moduleGap = 10; out.islandPad = 7; out.islandGap = 14; out.laneSpread = 0.72;
    } else if (id === "media") {
        lanes = { left: ["workspaces", "title"], center: ["media", "clock"], right: ["tray", "status", "indicators", "notifications", "quick"] };
        styles.media = "paper";
        out.layout = "islands"; out.floating = true; out.scale = 0.95; out.moduleGap = 12; out.islandPad = 9; out.islandGap = 16; out.laneSpread = 0.82;
    } else if (id === "dense") {
        out.layout = "strip"; out.floating = false; out.scale = 0.84; out.moduleGap = 7; out.islandPad = 4; out.islandGap = 0; out.laneSpread = 1;
        out.shape = "square";
    } else if (id === "default") {
        // Original Karuma visual recipe, translated onto the current renderer.
        // New capabilities stay available, but the shipped look remains the
        // continuous floating paper strip Karuma started with.
        out.opacity = 0.77;
        out.height = 38;
        out.layout = "strip";
        out.edge = "top";
        out.align = "center";
        out.length = 100;
        out.floating = true;
        out.shape = "rounded";
        out.cornerRadius = 12;
        out.innerRadiusBias = 0;
        out.borderWidth = 1;
        out.borderOpacity = 1;
        out.railWidth = 64;
        out.gap = { top: 4, bottom: 0, left: 24, right: 24 };
        out.moduleGap = 14;
        out.islandPad = 8;
        out.islandGap = 16;
        out.laneSpread = 1;
        out.textScale = 1;
        out.iconScale = 1;
        out.scale = 0.95;
        delete out.motion;
        out.hours = "12h";
        out.showClock = true;
        out.showDate = true;
        out.dateFormat = DEFAULT_DATE;
        out.indicator = "daily";
        // Keep the improved theme-aware progress treatment from current Karuma.
        out.progressStyle = "track";
        out.progressPlacement = "auto";
        out.progressThickness = 2;
        out.progressOpacity = 0.9;
        out.fullscreenMode = "hide";
        out.reserveSpace = true;
        out.workspaceStyle = DEFAULT_WORKSPACE_STYLE;
        delete out.displayFont;
        delete out.textFont;
        delete out.monoFont;
        delete out.jpFont;
    } else if (id === "rail") {
        out.layout = "islands"; out.edge = "right"; out.align = "center"; out.length = 92; out.floating = true; out.scale = 0.9; out.moduleGap = 8; out.islandPad = 6; out.islandGap = 12; out.laneSpread = 0.9; out.railWidth = 68;
        out.shape = "rounded";
    } else {
        return copyRaw(raw);
    }

    for (var li = 0; li < LANES.length; ++li) {
        var lane = LANES[li];
        lanes[lane] = (lanes[lane] || []).concat(pluginLanes[lane]);
    }

    var current = isObject(raw) && isObject(raw.modules) ? raw.modules : {};
    var next = copyRaw(current);
    next.lanes = normalizeLanes(lanes, null);
    next.hidden = normalizeHidden(hidden);
    next.styles = normalizeModuleStyles(styles);
    if (id === "default") {
        // A theme reset should not retain per-module tweaks that would make the
        // default look different. Plugin-specific tuning is user-owned and stays.
        var pluginOptions = {};
        for (var optionId in currentConf.moduleOptions)
            if (isPluginRef(optionId)) pluginOptions[optionId] = currentConf.moduleOptions[optionId];
        next.options = normalizeModuleOptions(pluginOptions);
    } else {
        next.options = normalizeModuleOptions(currentConf.moduleOptions);
    }
    delete next.order;
    out.modules = next;
    return out;
}

// Show or hide one control of the quick settings menu.
function withQuickHidden(raw, id, hide) {
    if (QUICK_IDS.indexOf(id) < 0) return copyRaw(raw);
    var hidden = normalize(raw).quickHidden.filter(function (h) { return h !== id; });
    if (hide) hidden.push(id);
    var out = copyRaw(raw);
    var q = copyRaw(isObject(raw) && isObject(raw.quick) ? raw.quick : {});
    q.hidden = normalizeQuick(hidden);
    out.quick = q;
    return out;
}

// Back to the shipped value of one hub page, or of everything the hub edits.
// Keys the hub never touches (height, typeSize, sealGlyph, ...) always stay.
var RESET_KEYS = {
    modules: ["modules"],
    spacing: ["gap", "moduleGap", "islandPad", "islandGap"],
    appearance: ["opacity", "height", "layout", "floating", "shape", "cornerRadius", "innerRadiusBias", "borderWidth", "borderOpacity", "scale", "motion", "workspaceStyle"],
    geometry: ["edge", "align", "length", "railWidth", "laneSpread"],
    typography: ["textScale", "iconScale", "displayFont", "textFont", "monoFont", "jpFont"],
    clock: ["hours", "showClock", "showDate", "dateFormat"],
    indicator: ["indicator", "progressStyle", "progressPlacement", "progressThickness", "progressOpacity"],
    behavior: ["fullscreenMode", "reserveSpace"],
    quick: ["quick"]
};

function withoutKaruma(raw, which) {
    var out = copyRaw(raw);
    var keys = RESET_KEYS[which];
    if (!keys) {
        keys = [];
        for (var page in RESET_KEYS) keys = keys.concat(RESET_KEYS[page]);
    }
    for (var i = 0; i < keys.length; ++i) delete out[keys[i]];
    return out;
}

function moduleById(id) {
    for (var i = 0; i < MODULES.length; ++i) if (MODULES[i].id === id) return MODULES[i];
    return null;
}

// Enabled refs in each lane. Plugin refs stay in the data even while disabled;
// the runtime plugin host decides whether they currently draw.
function zones(cfg) {
    var out = { left: [], center: [], right: [], clock: false };
    for (var i = 0; i < LANES.length; ++i) {
        var lane = LANES[i];
        var src = cfg.lanes[lane] || [];
        for (var j = 0; j < src.length; ++j) {
            var id = src[j];
            if (cfg.hidden.indexOf(id) >= 0) continue;
            if (id === "clock" && cfg.showClock === false && cfg.showDate === false) continue;
            out[lane].push(id);
        }
    }
    out.clock = out.left.indexOf("clock") >= 0 || out.center.indexOf("clock") >= 0 || out.right.indexOf("clock") >= 0;
    return out;
}

function styleFor(cfg, id) {
    var v = cfg && cfg.moduleStyles ? cfg.moduleStyles[String(id)] : undefined;
    return MODULE_STYLES.indexOf(String(v)) >= 0 ? String(v) : "plain";
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { MODULES: MODULES, DEFAULT_ORDER: DEFAULT_ORDER, DEFAULT_LANES: DEFAULT_LANES, LANES: LANES,
        MODULE_STYLES: MODULE_STYLES, PRESETS: PRESETS, SHAPES: SHAPES, LAYOUTS: LAYOUTS, EDGES: EDGES, SIDES: SIDES, ALIGNS: ALIGNS,
        PROGRESS_STYLES: PROGRESS_STYLES, PROGRESS_PLACEMENTS: PROGRESS_PLACEMENTS, FULLSCREEN_MODES: FULLSCREEN_MODES,
        QUICK: QUICK, INDICATORS: INDICATORS, WORKSPACE_STYLES: WORKSPACE_STYLES,
        DEFAULT_WORKSPACE_STYLE: DEFAULT_WORKSPACE_STYLE, normalizeWorkspaceStyle: normalizeWorkspaceStyle,
        workspaceText: workspaceText, DATE_PRESETS: DATE_PRESETS, DEFAULT_DATE: DEFAULT_DATE,
        SCALE_MIN: SCALE_MIN, SCALE_MAX: SCALE_MAX,
        defaults: defaults, normalize: normalize, normalizeOrder: normalizeOrder, normalizeLanes: normalizeLanes,
        flattenLanes: flattenLanes, normalizeHidden: normalizeHidden, normalizeModuleStyles: normalizeModuleStyles, normalizeModuleOptions: normalizeModuleOptions,
        normalizeQuick: normalizeQuick, normalizeDate: normalizeDate, splitDate: splitDate,
        moduleRefValid: moduleRefValid, isPluginRef: isPluginRef, laneOf: laneOf, styleFor: styleFor, moduleOptions: moduleOptions,
        withValue: withValue, withGap: withGap, withHidden: withHidden, withMoved: withMoved, withPlaced: withPlaced,
        withModuleStyle: withModuleStyle, withModuleOption: withModuleOption, withPreset: withPreset, withModules: withModules, withQuickHidden: withQuickHidden, withoutKaruma: withoutKaruma,
        zones: zones, moduleById: moduleById };
}
