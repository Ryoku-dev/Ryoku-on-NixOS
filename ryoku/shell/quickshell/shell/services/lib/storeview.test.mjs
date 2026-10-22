import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { storeViewUrl } = require("./storeview.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

const digest = "a".repeat(64);
const engawa = { id: "engawa", version: "1.0.0", preview: "", view: "dock-views/engawa/" + digest };
const ito = { id: "ito", version: "1.0.0", preview: "", view: "osd-views/ito/" + digest };

eq(storeViewUrl([engawa], "engawa", "/s", "dock-views", "Dock.qml"),
    "file:///s/dock-views/engawa/" + digest + "/Dock.qml",
    "an installed product runs the entry of its own view");
eq(storeViewUrl([ito], "ito", "/s", "osd-views", "Osd.qml"),
    "file:///s/osd-views/ito/" + digest + "/Osd.qml",
    "every category resolves through the same rule");
eq(storeViewUrl([engawa], "kumo", "/s", "dock-views", "Dock.qml"), "",
    "a product the store has not installed names nothing");
eq(storeViewUrl([{ ...engawa, id: "kumo" }], "kumo", "/s", "dock-views", "Dock.qml"), "",
    "a row cannot borrow another product's view");
eq(storeViewUrl([ito], "ito", "/s", "sidebar-views", "Sidebar.qml"), "",
    "a row cannot run from another category's views");
eq(storeViewUrl([{ ...engawa, view: "dock-views/engawa/../../x" }], "engawa", "/s", "dock-views", "Dock.qml"), "",
    "a view outside the category's views is refused");
eq(storeViewUrl([{ ...engawa, version: "" }], "engawa", "/s", "dock-views", "Dock.qml"), "",
    "a row without a version is refused");
eq(storeViewUrl([engawa], "engawa", "/s", "dock-views", "../Dock.qml"), "",
    "an entry that is not a plain file name is refused");
eq(storeViewUrl(null, "engawa", "/s", "dock-views", "Dock.qml"), "",
    "a missing index names nothing");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
