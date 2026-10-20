import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const Policy = require("./UrgentUpdatePolicy.js");

let failed = 0;

function eq(actual, expected, message) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        console.error(`FAIL: ${message}; got ${JSON.stringify(actual)}, want ${JSON.stringify(expected)}`);
        failed++;
    }
}

const lock = { commit: "aaaaaaa", subject: "[global] lock: fix", reason: "the lock screen opened without a password" };
const older = { commit: "bbbbbbb", subject: "[ryoku] net: fix", reason: "" };
const hour = 60 * 60 * 1000;
const now = 100 * hour;

eq(Policy.due([], {}, now, true), null, "nothing urgent, nothing shown");
eq(Policy.due(null, {}, now, true), null, "a frame without urgent shows nothing");
eq(Policy.due([lock], {}, now, true), lock, "a new urgent commit shows at once");
eq(Policy.due([lock], {}, now, false), null, "the switch off keeps it quiet");
eq(Policy.due([lock], { aaaaaaa: now - hour }, now, true), null, "closed an hour ago: snoozed");
eq(Policy.due([lock], { aaaaaaa: now - Policy.remindAfterMs }, now, true), lock, "comes back once the snooze runs out");
eq(Policy.due([lock, older], { bbbbbbb: now }, now, true), lock, "a newer urgent commit shows despite an older snooze");
eq(Policy.due([{ reason: "no commit" }], {}, now, true), null, "an entry without a commit is ignored");

eq(Policy.prune({ aaaaaaa: 1, bbbbbbb: 2 }, [lock]), { aaaaaaa: 1 }, "an installed commit leaves the state");
eq(Policy.prune({ aaaaaaa: 1 }, []), {}, "an update clears everything");

eq(Policy.reasons([lock, older], 3), [lock.reason, older.subject], "the subject stands in for a missing reason");
eq(Policy.reasons([lock, lock, lock, lock], 3).length, 3, "at most max lines");

if (failed) {
    console.error(`${failed} check(s) failed`);
    process.exit(1);
}
console.log("UrgentUpdatePolicy: ok");
