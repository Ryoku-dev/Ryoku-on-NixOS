import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { edgeRect, reserve, edgeForTrigger, cardPlacement, seamSpec, seamLeft, seamPlacement } = require("./RailGeometry.js");

let failed = 0;
function ok(cond, msg) {
    if (cond) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg); }
}
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

const width = 1920;
const height = 1080;
eq(edgeRect("top", 32, width, height), { x: 0, y: 0, width: 1920, height: 32 }, "top rail rect");
eq(edgeRect("bottom", 32, width, height), { x: 0, y: 1048, width: 1920, height: 32 }, "bottom rail rect");
eq(edgeRect("left", 48, width, height), { x: 0, y: 0, width: 48, height: 1080 }, "left rail rect");
eq(edgeRect("right", 48, width, height), { x: 1872, y: 0, width: 48, height: 1080 }, "right rail rect");
eq(reserve("left", 9, 48, true), 57, "left reserve includes frame lip");
eq(reserve("right", 9, 48, false), 0, "disabled rail reserves nothing");
eq({ top: reserve("top", 9, 32, true), left: reserve("left", 9, 48, true) }, { top: 41, left: 57 }, "top and left reserve independently");
const frameLip = 9;
const activeBottomInset = reserve("bottom", frameLip, 32, true) || frameLip;
const plainBottomInset = reserve("bottom", frameLip, 32, false) || frameLip;
eq(activeBottomInset, 41, "OSD clears an active bottom rail");
eq(plainBottomInset, 9, "OSD falls back to the frame lip");

const topBar = { top: 52, left: 0, bottom: 0, right: 0 };
const rails = { top: 41, left: 57, bottom: 41, right: 57 };
eq(edgeForTrigger(1400, 26, width, height, topBar), "top", "a top bar widget welds to the top");
eq(edgeForTrigger(1400, 1054, width, height, { bottom: 52 }), "bottom", "a bottom bar widget welds to the bottom");
eq(edgeForTrigger(20, 1060, width, height, rails), "bottom", "the bottom rail owns its corner over the left rail");
eq(edgeForTrigger(20, 1060, width, height, { left: 57 }), "left", "a lone left rail keeps a widget at its bottom");
eq(edgeForTrigger(20, 20, width, height, { top: 41, left: 57 }), "top", "the top rail owns its corner over the left rail");
eq(edgeForTrigger(960, 41, width, height, { top: 41 }), "top", "the rail depth is inclusive");
eq(edgeForTrigger(5, 540, width, height, { left: 0, top: 52 }), "left", "an edge without a rail only wins as the nearest");
eq(edgeForTrigger(20, 600, width, height, rails), "left", "a left rail widget welds to the left");
eq(edgeForTrigger(1900, 600, width, height, rails), "right", "a right rail widget welds to the right");
eq(edgeForTrigger(1880, 700, width, height, topBar), "right", "outside every rail the nearest edge wins");
eq(edgeForTrigger(960, 540, width, height, undefined), "top", "no clearances fall back to the nearest edge");

const gap = 12;
const card = 688;
const tall = 620;
const mark = (x, y) => ({ x, y, width: 20, height: 22 });
eq(cardPlacement(null, width, height, topBar, gap, card, tall),
    { edge: "top", corner: true, x: "left", left: 12, y: "top", top: 64 }, "no trigger keeps the top-left corner");
eq(cardPlacement(null, width, height, rails, gap, card, tall),
    { edge: "top", corner: true, x: "left", left: 69, y: "top", top: 53 }, "no trigger clears the rails");
eq(cardPlacement(mark(1400, 15), width, height, topBar, gap, card, tall),
    { edge: "top", x: "left", left: 1066, y: "top", top: 64 }, "a top bar trigger centres the card under it");
eq(cardPlacement(mark(10, 15), width, height, topBar, gap, card, tall),
    { edge: "top", x: "left", left: 12, y: "top", top: 64 }, "a trigger at the left end keeps the card on screen");
eq(cardPlacement(mark(1890, 15), width, height, topBar, gap, card, tall),
    { edge: "top", x: "left", left: 1220, y: "top", top: 64 }, "a trigger at the right end keeps the card on screen");
eq(cardPlacement(mark(900, 1043), width, height, { bottom: 52 }, gap, card, tall),
    { edge: "bottom", x: "left", left: 566, y: "bottom", bottom: 64 }, "a bottom bar trigger hangs the card above it");
eq(cardPlacement(mark(10, 200), width, height, rails, gap, card, tall),
    { edge: "left", x: "left", left: 69, y: "top", top: 200 }, "a high left rail trigger hangs the card down from it");
eq(cardPlacement(mark(10, 900), width, height, rails, gap, card, tall),
    { edge: "left", x: "left", left: 69, y: "bottom", bottom: 158 }, "a low left rail trigger stands the card up from it");
eq(cardPlacement(mark(1890, 410), width, height, { right: 57 }, gap, card, tall),
    { edge: "right", x: "right", right: 69, y: "top", top: 410 }, "a right rail trigger opens the card beside it");
eq(cardPlacement(mark(900, 1050), width, height, topBar, gap, card, tall),
    { edge: "bottom", x: "left", left: 566, y: "bottom", bottom: 42 }, "a trigger outside every rail is never covered");

// Whether the whole card lies inside the rails and the gap.
function inside(place, clearances, cardWidth, cardHeight) {
    const c = Object.assign({ top: 0, left: 0, bottom: 0, right: 0 }, clearances);
    const left = place.x === "left" ? place.left : width - place.right - cardWidth;
    const top = place.y === "top" ? place.top : height - place.bottom - cardHeight;
    return left >= c.left + gap && left + cardWidth <= width - c.right - gap
        && top >= c.top + gap && top + cardHeight <= height - c.bottom - gap;
}
eq(cardPlacement(mark(10, 520), width, height, rails, gap, card, tall),
    { edge: "left", x: "left", left: 69, y: "top", top: 407 }, "a mid rail trigger lifts the card to stay on screen");
eq(cardPlacement(mark(10, 560), width, height, rails, gap, card, tall),
    { edge: "left", x: "left", left: 69, y: "bottom", bottom: 407 }, "below the middle the card stands up and stays on screen");
for (const y of [41, 300, 520, 529, 530, 560, 800, 1017])
    ok(inside(cardPlacement(mark(10, y), width, height, rails, gap, card, tall), rails, card, tall),
        "a left rail trigger at y=" + y + " keeps the card inside the rails");
eq(cardPlacement(mark(10, 200), width, height, rails, gap, card, 1000).top, 53,
    "a card taller than the room left starts at the top rail");
const reach = { x: 900, y: 10, width: 20, height: 80 };
eq(cardPlacement(reach, width, height, topBar, gap, card, tall).top, 102,
    "a trigger reaching past its bar is not covered");
ok(inside(cardPlacement(reach, width, height, topBar, gap, card, 1004), topBar, card, 1004),
    "a trigger reaching past its bar never pushes a full card off screen");
ok(inside(cardPlacement(mark(5, 530), width, height, {}, gap, card, tall), {}, card, tall),
    "without any rail a floating trigger keeps the card on screen");

const naht = { edge: "top", depth: 52, fillet: 17, radius: 23, margin: 49, fill: "surface" };
eq(seamSpec(naht), naht, "a top seam with a depth is kept as declared");
eq(seamSpec(undefined), null, "no seam keeps the floating cards");
eq(seamSpec({ edge: "bottom", depth: 52 }), null, "only a top seam welds");
eq(seamSpec({ edge: "top", depth: "deep" }), null, "a seam needs a numeric depth");
eq(seamSpec({ edge: "top", depth: 0.5 }), null, "a seam needs a real depth");
eq(seamSpec({ edge: "top", depth: 52, fillet: 17, margin: 4 }).margin, 17, "the margin is never narrower than the fillet");
eq(seamSpec({ edge: "top", depth: 52, fill: "red" }).fill, "surface", "only surface roles fill a seam");
eq(seamSpec({ edge: "top", depth: 52, fill: "surfaceContainer" }).fill, "surfaceContainer", "a surface role is kept");
eq(seamSpec({ edge: "top", depth: 52, fillet: -3 }).fillet, 0, "a negative fillet reads as none");
eq(seamLeft(960, 300, width, 49), 810, "a welded card centres on its trigger");
eq(seamLeft(20, 300, width, 49), 49, "a welded card keeps the margin on the left");
eq(seamLeft(1900, 300, width, 49), 1571, "a welded card keeps the margin on the right");
eq(seamLeft(960, 1900, width, 49), 49, "a card wider than the room starts at the margin");
eq(seamPlacement(mark(727, 15), width, height, topBar, naht, gap, card, tall),
    { edge: "top", welded: true, corner: false, x: "left", left: 393, y: "top", top: 52 },
    "a bar trigger hangs the card flush from the seam");
eq(seamPlacement(null, width, height, topBar, naht, gap, card, tall),
    { edge: "top", welded: true, corner: true, x: "left", left: 49, y: "top", top: 52 },
    "without a trigger the card welds at the left margin");
eq(seamPlacement(mark(1890, 15), width, height, topBar, naht, gap, card, tall).left, 1183,
    "a trigger at the right end keeps the margin");
eq(seamPlacement(mark(900, 1050), width, height, topBar, naht, gap, card, tall).welded, false,
    "a trigger off the top edge keeps the floating card");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
