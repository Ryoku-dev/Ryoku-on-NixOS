import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const script = fs.readFileSync(new URL("./StoreDesignGalleryModel.js", import.meta.url), "utf8");
const context = {};
vm.runInNewContext(script.replace(".pragma library", ""), context);
const model = (shipped, catalogue) => JSON.parse(JSON.stringify(context.cardModel(shipped, catalogue)));
const karuma = { id: "karuma", name: "Karuma", desc: "The Karuma bar shipped with Ryoku on NixOS." };

test("Karuma is installed even when the Store omits it", () => {
    const result = model([karuma], []);
    assert.equal(result.length, 1);
    assert.equal(result[0].id, "karuma");
    assert.equal(result[0].installed, true);
    assert.equal(result[0].unavailable, false);
});

test("Store cannot replace a bundled Karuma with a disabled download card", () => {
    const store = [{ id: "karuma", name: "Karuma", installed: false,
        unavailable: true, unavailableEdition: true, updateAvailable: true,
        downloadPaused: true, unavailableReason: "not supported" }];
    const result = model([karuma], store);
    assert.equal(result.length, 1);
    assert.equal(result[0].name, "Karuma");
    assert.equal(result[0].installed, true);
    assert.equal(result[0].unavailable, false);
    assert.equal(result[0].updateAvailable, false);
    assert.equal(result[0].downloadPaused, false);
    assert.equal(result[0].desc, karuma.desc);
});

test("Installed Store metadata cannot disable a bundled bar", () => {
    const result = model([karuma], [{ id: "karuma", installed: true, unavailable: true }]);
    assert.equal(result[0].installed, true);
    assert.equal(result[0].unavailable, false);
});

test("Ordinary RyoStore extras retain their installed state", () => {
    const other = { id: "aftermarket", name: "Extra", installed: false, unavailable: true };
    const result = model([karuma], [other]);
    assert.equal(result.length, 2);
    assert.equal(result[1].installed, false);
    assert.equal(result[1].unavailable, true);
});

test("Duplicate catalogue entries do not duplicate shipped cards", () => {
    const result = model([karuma], [
        { id: "karuma", installed: false }, { id: "karuma", installed: true }
    ]);
    assert.equal(result.length, 1);
    assert.equal(result[0].installed, true);
});
