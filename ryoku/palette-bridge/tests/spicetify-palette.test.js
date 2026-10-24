"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const properties = new Map();
const elements = new Map();
const streams = [];
const events = [];
const timers = [];
let writes = 0;
class EventSource {
  constructor(url) {
    this.url = url;
    this.closed = false;
    streams.push(this);
  }
  close() {
    this.closed = true;
  }
}
class CustomEvent {
  constructor(type, options) {
    this.type = type;
    this.detail = options.detail;
  }
}
const document = {
  documentElement: { style: { setProperty: (name, value) => { writes++; properties.set(name, value); } } },
  getElementById: id => elements.get(id) || null,
  createElement: () => ({}),
  head: { appendChild: element => elements.set(element.id, element) },
};
const window = { dispatchEvent: event => events.push(event) };
const setTimeout = (callback, delay) => {
  timers.push({ callback, delay });
  return timers.length;
};
const source = fs.readFileSync(
  path.join(__dirname, "..", "spicetify", "ryoku-wallpaper-colors.js"),
  "utf8",
);
vm.runInNewContext(source, {
  window, document, EventSource, CustomEvent, JSON, Object, setTimeout,
});

assert.equal(streams.length, 2);
const paletteStream = streams.find(s => s.url === "http://127.0.0.1:47616/v1/events");
const preferencesStream = streams.find(s => s.url === "http://127.0.0.1:47616/v1/preferences/events");
assert.ok(paletteStream);
assert.ok(preferencesStream);
const defaults = { neutralStyle: false, accentStrength: 100, surfaceTint: 5, neutralText: true, removeGradients: true };
function preferences(values) {
  preferencesStream.onmessage({ data: JSON.stringify({ spotify: { ...defaults, ...values } }) });
}
assert.ok(elements.get("ryoku-wallpaper-token-bridge").textContent.includes("--encore-focus-outline-color"));

const palette = {
  primary: "#112233", onSurface: "#eeeeee", onSurfaceVariant: "#cccccc",
  background: "#010203", surface: "#111213", surfaceContainer: "#212223",
  surfaceContainerHigh: "#313233", surfaceContainerHighest: "#414243",
  surfaceContainerLow: "#090a0b", shadow: "#000000", primaryContainer: "#445566",
  outlineVariant: "#777777", tertiary: "#abcdef", error: "#ff0000",
  surfaceVariant: "#515253", secondary: "#778899",
};
paletteStream.onmessage({ data: JSON.stringify(palette) });

assert.equal(properties.get("--spice-text"), palette.onSurface, "default keeps the original text mapping");
assert.equal(properties.get("--spice-main"), palette.background, "default keeps the original palette surfaces");
assert.equal(properties.get("--spice-button"), palette.primary);
assert.ok(!elements.get("ryoku-wallpaper-token-bridge").textContent.includes(".main-home-homeHeader"));
preferences({ neutralStyle: true });
assert.ok(elements.get("ryoku-wallpaper-token-bridge").textContent.includes(".main-home-homeHeader"));
function luminance(hex) {
  const c = [1, 3, 5].map(i => {
    const v = parseInt(hex.slice(i, i + 2), 16) / 255;
    return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  });
  return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
}
function contrast(a, b) {
  const l = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (l[0] + 0.05) / (l[1] + 0.05);
}
assert.equal(properties.get("--spice-text"), "#f1f1f3", "body text stays neutral");
assert.equal(properties.get("--spice-subtext"), "#b6b8c0");
assert.notEqual(properties.get("--spice-main"), palette.background, "wallpaper backgrounds are not poured over the UI");
assert.ok(contrast(properties.get("--spice-button"), properties.get("--spice-main")) >= 4.5);
assert.ok(contrast(properties.get("--spice-text"), properties.get("--spice-card")) >= 7);
assert.equal(properties.get("--spice-primary"), properties.get("--spice-button"));
assert.equal(properties.get("--spice-progress-fg"), properties.get("--spice-button"));
assert.equal(events.at(-1).type, "ryoku-palette-changed");
assert.deepEqual(events.at(-1).detail, palette, "the complete source palette remains available to integrations");
const initialWrites = writes;
paletteStream.onmessage({ data: JSON.stringify(palette) });
assert.equal(writes, initialWrites, "identical palettes do not cause repaint churn");
const eventCount = events.length;
paletteStream.onmessage({ data: JSON.stringify({ ...palette, secondary: "#abcdef" }) });
assert.equal(writes, initialWrites, "unused role changes do not repaint surfaces");
assert.equal(events.length, eventCount + 1, "other integrations still receive the full palette event");
paletteStream.onmessage({ data: JSON.stringify({ ...palette, primary: "#ffb4a8" }) });
assert.equal(properties.get("--spice-button"), "#ffb4a8", "readable wallpaper accents keep their hue");
assert.notEqual(properties.get("--spice-main"), palette.background);
assert.equal(properties.get("--spice-text"), "#f1f1f3");
assert.equal(properties.get("--spice-rgb-button"), "255,180,168");
for (const primary of ["#000000", "#0000ff", "#ffffff", "#002200"]) {
  paletteStream.onmessage({ data: JSON.stringify({ ...palette, primary }) });
  assert.ok(contrast(properties.get("--spice-button"), properties.get("--spice-card")) >= 4.5, primary);
}
const validWrites = writes;
paletteStream.onmessage({ data: JSON.stringify({ primary: "invalid" }) });
assert.equal(writes, validWrites, "invalid palette cannot replace the current colors");
preferences({});
assert.equal(properties.get("--spice-main"), palette.background, "settings still work after an invalid palette event");

// Settings apply without a new palette event or app reload, and off restores the original.
paletteStream.onmessage({ data: JSON.stringify(palette) });
preferences({ neutralStyle: true, surfaceTint: 0, accentStrength: 0, neutralText: false, removeGradients: false });
assert.equal(properties.get("--spice-main"), "#131416");
assert.equal(properties.get("--spice-card"), "#222327");
assert.equal(properties.get("--spice-button"), "#c7c9d1");
assert.equal(properties.get("--spice-text"), palette.onSurface);
assert.ok(!elements.get("ryoku-wallpaper-token-bridge").textContent.includes(".main-home-homeHeader"));
preferences({ neutralStyle: true, surfaceTint: 20 });
assert.notEqual(properties.get("--spice-main"), "#131416");
// Surface controls and accent targets work independently, without palette events.
preferences({ neutralStyle: true, surfaceTint: 20 });
const tintedMain = properties.get("--spice-main");
const tintedCard = properties.get("--spice-card");
preferences({ neutralStyle: true, surfaceTint: 20, sidebarTint: 0, playerTint: 0, cardTint: 0 });
assert.equal(properties.get("--spice-sidebar"), "#17181b");
assert.equal(properties.get("--spice-player"), "#101113");
assert.equal(properties.get("--spice-card"), "#222327");
assert.equal(properties.get("--spice-main"), tintedMain);
assert.notEqual(tintedCard, properties.get("--spice-card"));
preferences({ neutralStyle: true, surfaceTint: 0, surfaceBrightness: 0 });
assert.equal(properties.get("--spice-main"), "#000000");
assert.equal(properties.get("--spice-card"), "#000000");
preferences({ neutralStyle: true, surfaceBrightness: 100 });
assert.ok(luminance(properties.get("--spice-main")) > luminance(tintedMain));
assert.ok(contrast(properties.get("--spice-button"), properties.get("--spice-card")) >= 4.5);
preferences({ neutralStyle: true, accentButtons: false });
assert.equal(properties.get("--spice-button"), "#c7c9d1");
assert.notEqual(properties.get("--spice-progress-fg"), "#c7c9d1");
preferences({ neutralStyle: true, accentProgress: false, accentLinks: false });
assert.notEqual(properties.get("--spice-button"), "#c7c9d1");
assert.equal(properties.get("--spice-progress-fg"), "#c7c9d1");
assert.equal(properties.get("--spice-pagelink-active"), "#c7c9d1");
assert.equal(properties.get("--spice-heart"), "#c7c9d1");
for (const token of ["text-bright-accent", "essential-bright-accent"]) {
  assert.ok(elements.get("ryoku-wallpaper-token-bridge").textContent.includes(`--${token}: var(--spice-pagelink-active)`));
}
for (const invalid of [{surfaceBrightness: 101}, {sidebarTint: -1}, {playerTint: "50"}, {cardTint: null}, {accentButtons: 1}]) {
  const previousWrites = writes;
  preferences({neutralStyle: true, ...invalid});
  assert.equal(writes, previousWrites, "invalid granular preferences preserve the rendered style");
}
const beforeInvalid = writes;
preferences({ neutralStyle: true, surfaceTint: 999 });
assert.equal(writes, beforeInvalid);
preferences({});
assert.equal(properties.get("--spice-main"), palette.background);
assert.equal(properties.get("--spice-card"), palette.surfaceContainer);
assert.equal(properties.get("--spice-text"), palette.onSurface);
assert.equal(properties.get("--spice-button"), palette.primary);
assert.ok(!elements.get("ryoku-wallpaper-token-bridge").textContent.includes('.Root__now-playing-bar { background:'));

paletteStream.onerror();
assert.equal(paletteStream.closed, true);
assert.equal(timers.length, 1);
assert.equal(timers[0].delay, 1000);
timers[0].callback();
assert.equal(streams.length, 3);
assert.equal(streams[2].url, "http://127.0.0.1:47616/v1/events");
preferencesStream.onerror();
assert.equal(preferencesStream.closed, true);
assert.equal(timers.length, 2);
timers[1].callback();
assert.equal(streams.length, 4);
assert.equal(streams[3].url, "http://127.0.0.1:47616/v1/preferences/events");
console.log("PASS: Spotify preserves defaults, applies opt-in preferences live, restores original styling and reconnects");
