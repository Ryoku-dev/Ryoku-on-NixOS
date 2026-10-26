import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const Subshells = require("./Subshells.js");
const styles = ["sumi", "iris", "python", "orpheus", "gokko", "tansu", "caelestia"]
    .map(id => ({ id }));

test("Bar Studio keeps every bar style", () => {
    assert.deepEqual(Subshells.visibleStyles(styles, false).map(style => style.id),
        ["sumi", "iris", "python", "orpheus", "gokko", "tansu", "caelestia"]);
});

test("Subshells keeps its focused projection", () => {
    assert.deepEqual(Subshells.visibleStyles(styles, true).map(style => style.id),
        ["python", "gokko", "tansu", "caelestia"]);
    assert.equal(Subshells.isStyle("iris"), false);
    assert.equal(Subshells.isStyle("python"), true);
});
