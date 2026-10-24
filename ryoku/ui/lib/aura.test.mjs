import assert from "node:assert/strict";
import test from "node:test";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { sectors, frame, follow } = require("./aura.js");

test("sectors folds any band count to twelve", () => {
    for (const m of [16, 64, 128]) {
        const levels = Array.from({ length: m }, (_, i) => i / (m - 1));
        const s = sectors(levels);
        assert.equal(s.length, 12, "twelve sectors for " + m + " bands");
        s.forEach((v) => assert.ok(v >= 0 && v <= 1, "sectors stay in 0..1"));
    }
});

test("a rising spectrum yields rising sectors", () => {
    const levels = Array.from({ length: 64 }, (_, i) => i / 63);
    const s = sectors(levels);
    for (let i = 1; i < s.length; i++)
        assert.ok(s[i] >= s[i - 1] - 1e-12, "sector " + i + " does not fall");
    assert.ok(s[11] > s[0], "the treble end reads louder than the bass end");
});

test("a single loud band lifts only its own sector", () => {
    const flat = new Array(64).fill(0.1);
    flat[32] = 1.0;
    const s = sectors(flat);
    const hit = Math.floor(32 / (64 / 12));
    for (let i = 0; i < 12; i++) {
        if (i === hit)
            assert.ok(s[i] > s[(i + 1) % 12] || s[i] > s[(i + 11) % 12],
                "the struck sector leads its neighbours");
        else
            assert.ok(s[i] < s[hit], "sector " + i + " stays under the struck one");
    }
});

test("empty input yields a silent field, not NaN", () => {
    for (const src of [[], null, undefined]) {
        const s = sectors(src);
        assert.equal(s.length, 12);
        s.forEach((v) => assert.equal(v, 0));
    }
});

test("a uniform frame flattens to a blob, a varied frame keeps contrast", () => {
    // the contrast pass is what stops every sector from moving equally; check
    // the spread it produces on a flat frame vs a spiky one.
    const flat = frame(new Array(12).fill(0.5));
    const spiky = frame([0.05, 0.9, 0.05, 0.05, 0.05, 0.05, 0.9, 0.05, 0.05, 0.05, 0.05, 0.05]);
    const spreadOf = (f) => Math.max(...f.levels) - Math.min(...f.levels);
    assert.ok(spreadOf(spiky) > spreadOf(flat),
        "a spiky frame spreads wider than a flat one");
});

test("energy weights the bass end", () => {
    const bass = frame(sectors(Array.from({ length: 64 }, (_, i) => i < 8 ? 1 : 0)));
    const treble = frame(sectors(Array.from({ length: 64 }, (_, i) => i >= 56 ? 1 : 0)));
    assert.ok(bass.energy > treble.energy, "same loudness, the bass half reads hotter");
});

test("frame stays in range on every input", () => {
    const raw = new Array(12).fill(0).map(() => Math.random());
    const f = frame(raw);
    assert.ok(f.energy >= 0 && f.energy <= 1);
    f.levels.forEach((v) => assert.ok(v >= 0 && v <= 1));
});

test("follow attacks fast, releases slow, and never overshoots", () => {
    const up = follow(0, 1, 0.016, 24, 8);
    const down = follow(1, 0, 0.016, 24, 8);
    assert.ok(up > 0 && up < 1, "a rising step lands short of the target");
    assert.ok(down < 1 && down > 0, "a falling step lands above zero");
    // the rates are per second: at equal dt the fast attack covers more ground.
    const attackMove = follow(0, 1, 0.016, 24, 8);
    const releaseMove = follow(1, 0, 0.016, 24, 8);
    assert.ok(attackMove > 1 - releaseMove, "attack outruns release");
    // converged: holding still moves nothing.
    assert.equal(follow(1, 1, 0.016, 24, 8), 1);
});

test("follow converges over a second of frames", () => {
    let v = 0;
    for (let i = 0; i < 60; i++)
        v = follow(v, 1, 1 / 60, 12, 3.2);
    assert.ok(v > 0.99, "60 frames of a 12/s attack reaches the target (got " + v + ")");
});
