import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { pin, unpin, resolve, storeDesignUrl } = require("./dock.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}

const clients = [
    { className: "firefox", address: "0x1" },
    { className: "kitty", address: "0x2" },
    { className: "firefox", address: "0x3" },
    { className: "steam", address: "0x4" }
];

eq(pin(["firefox"], "firefox"), ["firefox"], "duplicate pins are rejected");
eq(resolve(["kitty", "firefox"], clients), ["kitty", "firefox", "steam"], "pinned classes lead and live unpinned clients follow stably");
eq(resolve(["firefox"], clients), ["firefox", "kitty", "steam"], "live unpinned clients are inserted after pins");
eq(unpin(["firefox", "kitty"], "firefox"), ["kitty"], "unpin removes only the requested class");
eq(resolve(["firefox"], clients).some(value => value.includes("0x")), false, "window addresses are never persisted in dock entries");

const digest = "a".repeat(64);
const engawa = { id: "engawa", version: "1.0.0", preview: "", view: "dock-views/engawa/" + digest };
eq(storeDesignUrl([engawa], "engawa", "/s"), "file:///s/dock-views/engawa/" + digest + "/Dock.qml",
    "an installed store dock runs the Dock.qml of its own view");
eq(storeDesignUrl([engawa], "kumo", "/s"), "", "a design the store has not installed names nothing");
eq(storeDesignUrl([{ ...engawa, id: "kumo" }], "kumo", "/s"), "", "a row cannot borrow another dock's view");
eq(storeDesignUrl([{ ...engawa, view: "dock-views/engawa/../../x" }], "engawa", "/s"), "", "a view outside the dock views is refused");
eq(storeDesignUrl([{ ...engawa, version: "" }], "engawa", "/s"), "", "a row without a version is refused");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
