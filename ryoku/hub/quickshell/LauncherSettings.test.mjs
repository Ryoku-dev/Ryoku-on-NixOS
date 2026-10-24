import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
import test from "node:test";

const source = fs.readFileSync(new URL("./LauncherSettings.js", import.meta.url), "utf8");
const context = {};
vm.runInNewContext(source.replace(".pragma library", ""), context);
const parse = text => JSON.parse(JSON.stringify(context.parse(text)));

test("a descriptor keeps known capabilities and well-formed sections", () => {
    const got = parse(JSON.stringify({
        capabilities: ["overlay", "sections", "hiddenApps", "overlay", "teleport"],
        sections: [{ id: "internet", label: "Internet" }, { id: "dev-tools", label: "Develop" }]
    }));
    assert.deepEqual(got.capabilities, ["overlay", "sections", "hiddenApps"]);
    assert.deepEqual(got.sections.map(s => s.id), ["internet", "dev-tools"]);
});

test("a missing, empty or malformed file offers nothing", () => {
    for (const text of ["", "not json", "null", "[]", "42", undefined])
        assert.deepEqual(parse(text), { capabilities: [], sections: [] });
});

test("bad section rows are dropped, labels are bounded and repeats keep the first", () => {
    const got = parse(JSON.stringify({
        capabilities: ["sections"],
        sections: [
            { id: "Media", label: "Media" }, { id: "media", label: "" },
            { id: "media", label: "  Media  " }, { id: "media", label: "Again" },
            { id: "office" }, { id: "games", label: "Games\nNow" },
            { id: "long", label: "x".repeat(81) }, null, "utility"
        ]
    }));
    assert.deepEqual(got.sections, [{ id: "media", label: "Media" }]);
});

test("the sections capability needs sections to order", () => {
    const got = parse(JSON.stringify({ capabilities: ["sections", "grid"], sections: [] }));
    assert.deepEqual(got.capabilities, ["grid"]);
});

test("oversized descriptors are rejected before parsing", () => {
    assert.deepEqual(parse(`{"capabilities":[],"padding":"${"x".repeat(65536)}"}`),
        { capabilities: [], sections: [] });
});
