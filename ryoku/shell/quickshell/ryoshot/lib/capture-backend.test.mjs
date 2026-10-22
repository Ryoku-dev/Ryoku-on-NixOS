import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";

const require = createRequire(import.meta.url);
const { shouldUseGrim } = require("./capture-backend.js");

assert.equal(shouldUseGrim("", "niri", ""), true, "niri defaults to grim");
assert.equal(shouldUseGrim("", "NIRI:GNOME", ""), true, "desktop list is case insensitive");
assert.equal(shouldUseGrim("", "GNOME:niri", ""), true, "niri is found after other desktops");
assert.equal(shouldUseGrim("", "", "/run/user/1000/niri.sock"), true, "niri socket is enough");
assert.equal(shouldUseGrim("1", "Hyprland", ""), true, "explicit fallback works anywhere");
assert.equal(shouldUseGrim("0", "niri", ""), true, "niri always avoids the crash path");
assert.equal(shouldUseGrim("", "Hyprland", ""), false, "hyprland retains Quickshell capture");
assert.equal(shouldUseGrim("", "sway", ""), false, "other compositors retain Quickshell capture");

const qml = readFileSync(new URL("../Overlay.qml", import.meta.url), "utf8");
assert.match(qml, /active:\s*!overlay\.forceFallback/, "niri never instantiates the screencopy object");
assert.match(qml, /running:\s*!overlay\.forceFallback/, "niri does not poll screencopy");
assert.match(qml, /sourceComponent:\s*Component\s*\{\s*ScreencopyView/, "capture object is lazy");
assert.match(qml, /shotLoader\.item/, "normal capture uses the dynamically loaded object");
assert.equal((qml.match(/ScreencopyView\s*\{/g) || []).length, 1,
    "no second eager screencopy instance remains");
console.log("PASS Ryoshot capture backend policy and lazy Wayland source guard");
