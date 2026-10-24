import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { countOnActiveWorkspace } = require("./windowPresence.js");

let failed = 0;
function eq(actual, expected, message) {
    if (actual === expected) console.log("PASS " + message);
    else { failed++; console.log("FAIL " + message + "\n  expected " + expected + "\n  got      " + actual); }
}

const workspaces = [
    { id: "1", output: "eDP-1", is_active: true },
    { id: "2", output: "eDP-1", is_active: false },
    { id: "3", output: "DP-1", is_active: true }
];
const toplevel = minimized => ({ minimized });

const live = [
    { workspace: "1", toplevel: toplevel(false) },
    { workspace: "1", toplevel: toplevel(true) },
    { workspace: "2", toplevel: toplevel(false) },
    { workspace: "3", toplevel: toplevel(false) }
];
eq(countOnActiveWorkspace(live, workspaces, "eDP-1"), 1,
    "only unminimized toplevels on the output's active workspace count");
eq(countOnActiveWorkspace(live, workspaces, "DP-1"), 1,
    "each output uses its own active workspace");
eq(countOnActiveWorkspace(live, workspaces, "HDMI-A-1"), 0,
    "an output with no active workspace has no deck frost");

const joinLag = [
    { workspace: "1", appId: "kitty", title: "new title", toplevel: null },
    { workspace: "2", appId: "firefox", title: "other workspace" }
];
eq(countOnActiveWorkspace(joinLag, workspaces, "eDP-1"), 1,
    "a provider window stays present while its protocol handle catches up");
const switchedWorkspaces = [
    { id: "1", output: "eDP-1", is_active: false },
    { id: "2", output: "eDP-1", is_active: true }
];
eq(countOnActiveWorkspace(joinLag, switchedWorkspaces, "eDP-1"), 1,
    "a workspace switch immediately follows the newly active workspace");
eq(countOnActiveWorkspace([], workspaces, "eDP-1"), 0,
    "the frost clears when the provider removes the last window");

const minimized = [
    { workspace: "1", appId: "kitty", title: "terminal", toplevel: toplevel(true) }
];
eq(countOnActiveWorkspace(minimized, workspaces, "eDP-1"), 0,
    "a joined minimized window leaves the wallpaper clear");
eq(countOnActiveWorkspace(undefined, workspaces, "eDP-1"), 0,
    "missing window state fails open");
eq(countOnActiveWorkspace(live, undefined, "eDP-1"), 0,
    "missing workspace state fails open");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
