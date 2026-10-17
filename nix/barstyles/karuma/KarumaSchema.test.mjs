import { createRequire } from "node:module";
import assert from "node:assert/strict";
const S = createRequire(import.meta.url)("./KarumaSchema.js");

const shipped = {
  left: ["workspaces", "title"],
  center: ["clock"],
  right: ["media", "tray", "status", "indicators", "notifications", "quick"]
};

for (const raw of [undefined, null, [], "x", 5, {}]) {
  const c = S.normalize(raw);
  assert.equal(c.opacity, 0.77);
  assert.equal(c.height, 38);
  assert.equal(c.layout, "strip");
  assert.equal(c.edge, "top");
  assert.equal(c.align, "center");
  assert.equal(c.length, 100);
  assert.equal(c.floating, true);
  assert.equal(c.shape, "rounded");
  assert.equal(c.cornerRadius, 12);
  assert.equal(c.innerRadiusBias, 0);
  assert.equal(c.borderWidth, 1);
  assert.equal(c.borderOpacity, 1);
  assert.equal(c.railWidth, 64);
  assert.deepEqual(c.gap, { top: 4, bottom: 0, left: 24, right: 24 });
  assert.deepEqual(c.lanes, shipped);
  assert.deepEqual(c.hidden, []);
  assert.deepEqual(c.moduleStyles, {});
  assert.deepEqual(c.moduleOptions, {});
  assert.equal(c.moduleGap, 14);
  assert.equal(c.islandPad, 8);
  assert.equal(c.islandGap, 16);
  assert.equal(c.laneSpread, 1);
  assert.equal(c.textScale, 1);
  assert.equal(c.iconScale, 1);
  assert.equal(c.progressStyle, "track");
  assert.equal(c.progressPlacement, "auto");
  assert.equal(c.fullscreenMode, "hide");
  assert.equal(c.reserveSpace, true);
}

// Old clock-pivot configs migrate without losing the old visual ordering.
let c = S.normalize({ modules: { order: ["status", "clock", "title", "media", "workspaces", "indicators", "notifications", "quick"] } });
assert.deepEqual(c.lanes.left, ["status"]);
assert.deepEqual(c.lanes.center, ["clock"]);
assert.deepEqual(c.lanes.right, ["title", "media", "tray", "workspaces", "indicators", "notifications", "quick"]);

// Explicit lanes are repaired, de-duplicated and gain any missing built-ins.
c = S.normalize({ modules: { lanes: {
  left: ["status", "ryoku:weather", "status", "nonsense"],
  center: ["clock", "ryoku:weather"],
  right: ["media"]
}}});
assert.deepEqual(c.lanes.left, ["status", "ryoku:weather", "workspaces", "title"]);
assert.deepEqual(c.lanes.center, ["clock"]);
assert.deepEqual(c.lanes.right, ["media", "tray", "indicators", "notifications", "quick"]);
assert.equal(new Set(S.flattenLanes(c.lanes)).size, S.flattenLanes(c.lanes).length);

// Namespaced plugin refs are stable layout entries. Garbage is not.
assert.equal(S.moduleRefValid("ryoku:weather"), true);
assert.equal(S.moduleRefValid("omarchy:omarchy.audio"), true);
assert.equal(S.moduleRefValid("plugin:bad"), false);
assert.equal(S.moduleRefValid("ryoku:Bad"), false);

// Place/reorder across lanes.
let r = S.withPlaced({}, "clock", "right", 1);
c = S.normalize(r);
assert.deepEqual(c.lanes.center, []);
assert.equal(c.lanes.right[1], "clock");
r = S.withPlaced(r, "workspaces", "center", 0);
c = S.normalize(r);
assert.equal(c.lanes.center[0], "workspaces");
assert.equal(S.laneOf(c.lanes, "workspaces"), "center");
r = S.withPlaced(r, "ryoku:weather", "left", 0);
assert.equal(S.normalize(r).lanes.left[0], "ryoku:weather");

// Hiding works for built-ins and plugin refs and preserves placement.
r = S.withHidden(r, "ryoku:weather", true);
assert.ok(S.normalize(r).hidden.includes("ryoku:weather"));
r = S.withHidden(r, "ryoku:weather", false);
assert.ok(!S.normalize(r).hidden.includes("ryoku:weather"));

// Per-module treatments are sparse and validated.
r = S.withModuleStyle({}, "clock", "accent");
assert.equal(S.styleFor(S.normalize(r), "clock"), "accent");
r = S.withModuleStyle(r, "ryoku:weather", "outline");
assert.equal(S.styleFor(S.normalize(r), "ryoku:weather"), "outline");
r = S.withModuleStyle(r, "clock", "plain");
assert.equal(S.styleFor(S.normalize(r), "clock"), "plain");
assert.deepEqual(S.withModuleStyle({}, "clock", "lasers"), {});
assert.deepEqual(S.MODULE_STYLES, ["plain", "paper", "outline", "accent", "ghost"]);

// Every module also owns independent scale, padding and opacity.
r = S.withModuleOption({}, "clock", "scale", 1.25);
r = S.withModuleOption(r, "clock", "padding", 7);
r = S.withModuleOption(r, "clock", "opacity", 0.55);
c = S.normalize(r);
assert.deepEqual(S.moduleOptions(c, "clock"), { scale: 1.25, padding: 7, opacity: 0.55 });
r = S.withModuleOption(r, "ryoku:weather", "scale", 0.7);
assert.equal(S.moduleOptions(S.normalize(r), "ryoku:weather").scale, 0.7);
assert.deepEqual(S.withModuleOption({}, "clock", "nonsense", 1), {});

// Enabled zones follow the explicit lanes. Clock can be anywhere now.
c = S.normalize({ modules: { lanes: { left: ["clock", "workspaces"], center: ["media"], right: ["title", "status", "indicators", "notifications", "quick"] } } });
let z = S.zones(c);
assert.deepEqual(z.left.slice(0, 2), ["clock", "workspaces"]);
assert.equal(z.clock, true);
z = S.zones(S.normalize({ showClock: false, showDate: false, modules: { lanes: shipped } }));
assert.equal(z.clock, false);
assert.deepEqual(z.center, []);

// The shipped theme is the original Karuma continuous floating strip.
let dflt = S.defaults();
assert.equal(dflt.layout, "strip");
assert.equal(dflt.opacity, 0.77);
assert.equal(dflt.height, 38);
assert.equal(dflt.shape, "rounded");
assert.deepEqual(dflt.gap, { top: 4, bottom: 0, left: 24, right: 24 });
assert.equal(dflt.scale, 0.95);
assert.equal(S.PRESETS[0].id, "default");

// Curated presets are ordinary schema edits and remain fully editable afterwards.
r = S.withPreset({
  opacity: 0.3, height: 62, layout: "islands", shape: "pill", cornerRadius: 30,
  textScale: 1.4, iconScale: 1.3, displayFont: "Comic Sans MS", motion: "still",
  modules: {
    lanes: { left: ["workspaces", "title"], center: ["clock"], right: ["media", "tray", "status", "indicators", "notifications", "quick", "ryoku:test"] },
    styles: { workspaces: "accent", "ryoku:test": "outline" },
    options: { workspaces: { scale: 1.4, padding: 9, opacity: 0.5 }, "ryoku:test": { scale: 1.2, padding: 2, opacity: 0.8 } }
  }
}, "default");
c = S.normalize(r);
assert.equal(c.layout, "strip");
assert.equal(c.opacity, 0.77);
assert.equal(c.height, 38);
assert.equal(c.shape, "rounded");
assert.equal(c.scale, 0.95);
assert.equal(c.textScale, 1);
assert.equal(c.iconScale, 1);
assert.equal(c.moduleOptions.workspaces, undefined);
assert.equal(c.moduleOptions["ryoku:test"].scale, 1.2);
assert.equal(S.styleFor(c, "workspaces"), "plain");
assert.equal(S.styleFor(c, "ryoku:test"), "outline");
assert.equal(r.displayFont, undefined);

r = S.withPreset({ sealGlyph: "漢" }, "minimal");
c = S.normalize(r);
assert.deepEqual(c.hidden, ["title", "media", "tray", "indicators", "notifications"]);
assert.equal(r.sealGlyph, "漢");
r = S.withPreset({}, "media");
c = S.normalize(r);
assert.deepEqual(c.lanes.center, ["media", "clock"]);
assert.equal(S.styleFor(c, "media"), "paper");
r = S.withPreset({}, "dense");
c = S.normalize(r);
assert.equal(c.layout, "strip"); assert.equal(c.floating, false); assert.equal(c.moduleGap, 7);
r = S.withPreset({}, "rail");
c = S.normalize(r);
assert.equal(c.edge, "right"); assert.equal(c.layout, "islands"); assert.equal(c.railWidth, 68); assert.equal(c.laneSpread, 0.9);
// Profiles only retune built-ins. Plugin placement, hidden state and treatment survive.
r = S.withPreset({ modules: {
  lanes: { left: ["workspaces", "ryoku:vpn", "title"], center: ["clock"], right: ["media", "status", "indicators", "notifications", "quick", "omarchy:weather"] },
  hidden: ["ryoku:vpn"],
  styles: { "ryoku:vpn": "outline", "omarchy:weather": "accent" }
} }, "media");
c = S.normalize(r);
assert.equal(S.laneOf(c.lanes, "ryoku:vpn"), "left");
assert.equal(S.laneOf(c.lanes, "omarchy:weather"), "right");
assert.ok(c.hidden.includes("ryoku:vpn"));
assert.equal(S.styleFor(c, "ryoku:vpn"), "outline");
assert.equal(S.styleFor(c, "omarchy:weather"), "accent");
assert.deepEqual(S.withPreset({ custom: 1 }, "bogus"), { custom: 1 });

// Clamps.
c = S.normalize({ opacity: 9, height: 999, layout: "blob", edge: "ceiling", align: "wherever", length: 4, shape: "blob", floating: "yes",
  cornerRadius: 99, innerRadiusBias: -99, borderWidth: 99, borderOpacity: -2, railWidth: 999,
  moduleGap: 99, islandPad: -4, islandGap: 99, laneSpread: -4, textScale: 9, iconScale: 0.1,
  progressStyle: "laser", progressPlacement: "void", progressThickness: 99, progressOpacity: 0, fullscreenMode: "whatever", reserveSpace: "yes",
  gap: { top: -5, left: "12.6", right: "abc", bottom: 999 } });
assert.equal(c.opacity, 1);
assert.equal(c.height, 80);
assert.equal(c.layout, "strip");
assert.equal(c.edge, "top");
assert.equal(c.align, "center");
assert.equal(c.length, 28);
assert.equal(c.shape, "rounded");
assert.equal(c.floating, false);
assert.equal(c.cornerRadius, 48);
assert.equal(c.innerRadiusBias, -12);
assert.equal(c.borderWidth, 4);
assert.equal(c.borderOpacity, 0);
assert.equal(c.railWidth, 128);
assert.equal(c.moduleGap, 40);
assert.equal(c.islandPad, 0);
assert.equal(c.islandGap, 48);
assert.equal(c.laneSpread, 0);
assert.equal(c.textScale, 1.8);
assert.equal(c.iconScale, 0.65);
assert.equal(c.progressStyle, "track");
assert.equal(c.progressPlacement, "auto");
assert.equal(c.progressThickness, 8);
assert.equal(c.progressOpacity, 0.1);
assert.equal(c.fullscreenMode, "hide");
assert.equal(c.reserveSpace, false);
assert.deepEqual(c.gap, { top: 0, bottom: 64, left: 13, right: 24 });

// Edits never mutate input and preserve unrelated legacy keys.
const raw = { hours: "24h", sealGlyph: "漢", custom: { a: 1 } };
const frozen = JSON.stringify(raw);
r = S.withValue(raw, "opacity", 0.6);
r = S.withGap(r, "left", 20);
assert.equal(JSON.stringify(raw), frozen);
assert.equal(r.hours, "24h");
assert.equal(r.sealGlyph, "漢");
assert.deepEqual(r.custom, { a: 1 });
assert.equal(S.normalize(r).gap.left, 20);

// Reset ownership.
r = S.withoutKaruma({ height: 44, sealGlyph: "漢", hours: "24h", motion: "still", opacity: 0.5,
  gap: { top: 1 }, moduleGap: 20, islandPad: 12, modules: { lanes: shipped }, layout: "strip", floating: true,
  shape: "pill", scale: 1.3, showClock: false, showDate: false, dateFormat: "yyyy", indicator: "music",
  quick: { hidden: ["wifi"] } }, "all");
assert.deepEqual(r, { sealGlyph: "漢" });

// Clock/date, indicator, quick controls and workspace styles retain existing behaviour.
assert.equal(S.normalize({}).scale, 0.95);
assert.equal(S.normalize({ scale: 0.1 }).scale, S.SCALE_MIN);
assert.equal(S.normalize({ scale: 9 }).scale, S.SCALE_MAX);
assert.equal(S.normalize({ laneSpread: 9 }).laneSpread, 1);
assert.equal(S.normalize({ motion: "still" }).animations, false);
assert.equal(S.normalize({ hours: "24h" }).hours, "24h");
assert.equal(S.normalize({ showClock: false }).showClock, false);
assert.equal(S.normalize({ showDate: false }).showDate, false);
assert.deepEqual(S.splitDate("ddd|dd MMM"), { top: "ddd", bottom: "dd MMM" });
assert.deepEqual(S.splitDate("a|b|c"), { top: "a", bottom: "b c" });
for (const mode of S.INDICATORS) assert.equal(S.normalize({ indicator: mode }).indicator, mode);
c = S.normalize({ quick: { hidden: ["wifi", "wifi", "bogus", "mic"] } });
assert.deepEqual(c.quickHidden, ["wifi", "mic"]);
assert.equal(S.DEFAULT_WORKSPACE_STYLE, "kanji");
for (const w of S.WORKSPACE_STYLES) assert.equal(S.normalize({ workspaceStyle: w.id }).workspaceStyle, w.id);
assert.equal(S.workspaceText("numbers", "2", "弐"), "2");
assert.equal(S.workspaceText("roman", "4", "肆"), "Ⅳ");
assert.equal(S.workspaceText("dots", "3", "参"), "");

console.log("KarumaSchema: all assertions passed");

// The app tray is a normal movable built-in. A config that predates it gains it
// next to Now playing, and the old arrangement is otherwise untouched.
assert.ok(S.MODULES.some((m) => m.id === "tray"));
c = S.normalize({ modules: { lanes: { left: ["workspaces", "title"], center: ["clock"], right: ["status", "media", "quick"] } } });
assert.deepEqual(c.lanes.right, ["status", "media", "tray", "quick", "indicators", "notifications"]);
c = S.normalize({ modules: { lanes: { left: ["tray", "workspaces", "title"], center: ["clock"], right: ["media", "status", "indicators", "notifications", "quick"] } } });
assert.deepEqual(c.lanes.left, ["tray", "workspaces", "title"]);
assert.equal(S.flattenLanes(c.lanes).filter((id) => id === "tray").length, 1);
