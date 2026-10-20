import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { layout } = require("./filmstrip.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}
function ok(cond, msg) {
    if (cond) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}

const slots = (n, plus = true) => {
    const out = [];
    for (let i = 0; i < n; i++) out.push({ full: true });
    if (plus) out.push({ full: false });
    return out;
};
const gap = 12;
const slat = 56;

// 5120x1440 (32:9): aspect 0.28125, cells 11 % of the height.
const ultra = layout(slots(2), 1440 / 5120, 5120 - 98, 158, 84, slat, gap);
eq(ultra.cellH, 158, "an ultrawide keeps the full cell height for two workspaces");
eq(ultra.items[0], { x: 0, y: 0, w: 562, h: 158 }, "a 32:9 cell keeps the screen's shape");
eq(ultra.items[2].w, slat, "the add slot is a slat");
eq(ultra.height, 158, "one row");
const ten = layout(slots(10), 1440 / 5120, 5120 - 98, 158, 84, slat, gap);
eq(ten.height, ten.cellH, "ten workspaces still fit one row on an ultrawide");
ok(ten.width <= 5120 - 98, "the row stays inside the screen");

// 1920x1080.
const hd = layout(slots(4), 1080 / 1920, 1920 - 98, 119, 84, slat, gap);
eq(hd.cellH, 119, "four workspaces at 1080p keep the full height");
eq(hd.width, Math.round(4 * 119 * 1920 / 1080 + slat + 4 * gap), "the row is as wide as its cells");
const many = layout(slots(11), 1080 / 1920, 1920 - 98, 119, 84, slat, gap);
ok(many.cellH >= 84, "cells never get smaller than the minimum");
ok(many.height > many.cellH, "too many workspaces wrap to a second row");
for (const it of many.items)
    ok(it.x >= 0 && it.x + it.w <= many.width + 1, "a wrapped cell stays inside the block");

// 2560x1440 with one workspace.
const qhd = layout(slots(1), 1440 / 2560, 2560 - 98, 158, 84, slat, gap);
eq(qhd.items.length, 2, "one workspace and the add slot");
eq(qhd.width, Math.round(158 * 2560 / 1440 + slat + gap), "a single workspace makes a short strip");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
