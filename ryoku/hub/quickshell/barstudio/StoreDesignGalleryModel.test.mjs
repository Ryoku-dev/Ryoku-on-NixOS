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

// QML sometimes exposes shipped lists as sequence wrappers, not JS Arrays.
test("QML sequence wrappers retain bundled cards", () => {
    const wrapped = { 0: karuma, 1: { id: "sumi", name: "Sumi" }, length: 2 };
    const result = model(wrapped, []);
    assert.deepEqual(result.map(card => card.id), ["karuma", "sumi"]);
});

test("the final Bar Studio gallery includes Karuma without a Store receipt", () => {
    const result = JSON.parse(JSON.stringify(context.galleryCards("barstyles", [], [
        { id: "orpheus", installed: true }, { id: "sumi", installed: true }
    ])));
    assert.deepEqual(result.map(card => card.id), ["karuma", "orpheus", "sumi"]);
    assert.equal(result[0].installed, true);
    assert.equal(result[0].unavailable, false);
});

test("final gallery retains exactly one Karuma against hostile Store metadata", () => {
    const result = JSON.parse(JSON.stringify(context.galleryCards("barstyles", [karuma], [
        { id: "karuma", installed: false, unavailable: true, updateAvailable: true },
        { id: "python", installed: true }
    ])));
    assert.deepEqual(result.map(card => card.id), ["karuma", "python"]);
    assert.equal(result[0].installed, true);
    assert.equal(result[0].unavailable, false);
});

test("non-bar galleries do not acquire a Karuma card", () => {
    const result = JSON.parse(JSON.stringify(context.galleryCards("osd", [], [
        { id: "ryoku", installed: true }
    ])));
    assert.deepEqual(result.map(card => card.id), ["ryoku"]);
});

test("the live QML gallery calls the tested final model", () => {
    const gallery = fs.readFileSync(new URL("../pages/StoreDesignGallery.qml", import.meta.url), "utf8");
    assert.match(gallery, /GalleryModel\.galleryCards\(gallery\.category, gallery\.shippedDesigns, gallery\.catalogueDesigns\)/);
});

test("Python panels honour the per-display style selection", () => {
    const bar = fs.readFileSync(new URL("../../../shell/quickshell/shell/modules/bar/barstyles/python/bar/Bar.qml", import.meta.url), "utf8");
    assert.match(bar, /Shell\.Config\.barStyleFor\(screen\.name\) === "python"/);
    assert.match(bar, /Tokens\.barEnabledFor\(screen\.name\)/);
});
