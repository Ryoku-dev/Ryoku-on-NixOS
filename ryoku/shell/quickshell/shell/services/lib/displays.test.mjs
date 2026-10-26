import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { connectorSignature } = require("./displays.js");

let failed = 0;
function ok(cond, message) {
    if (cond) console.log("PASS " + message);
    else { failed++; console.log("FAIL " + message); }
}

const dp = { name: "DP-1", make: "Dell", model: "U2723QE", width: 2560, height: 1440, scale: 1 };
const hdmi = { name: "HDMI-A-1", make: "LG", model: "27GL850", width: 2560, height: 1440, scale: 1 };

ok(connectorSignature([Object.assign({}, dp, { activeWorkspace: "1", focused: true })])
    === connectorSignature([Object.assign({}, dp, { activeWorkspace: "2", focused: false })]),
    "a workspace switch or focus move keeps the signature");
ok(connectorSignature([Object.assign({}, dp, { scale: 1.5, width: 1707, x: 100 })]) === connectorSignature([dp]),
    "a mode, scale or position change keeps the signature");
ok(connectorSignature([dp, hdmi]) === connectorSignature([hdmi, dp]),
    "output order does not matter");
ok(connectorSignature([dp]) !== connectorSignature([dp, hdmi]),
    "plugging a display in changes the signature");
ok(connectorSignature([dp, hdmi]) !== connectorSignature([hdmi]),
    "unplugging a display changes the signature");
ok(connectorSignature([dp]) !== connectorSignature([Object.assign({}, dp, { make: "LG", model: "27GL850" })]),
    "a different monitor on the same connector changes the signature");
ok(connectorSignature(null) === connectorSignature([]),
    "a missing output list reads as no outputs");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
