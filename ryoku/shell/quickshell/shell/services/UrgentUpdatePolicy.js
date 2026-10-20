// When the urgent-update alert shows. The live service (UrgentUpdates.qml) and
// its unit test use this same policy.
//
// alerts is the `urgent` list of the daemon's updates frame, newest first:
// [{ commit, subject, reason }]. shown maps a commit to the time (ms) its
// alert last closed. The alert names the newest urgent commit; a commit it has
// not shown for comes up at once, and a closed one comes back after
// remindAfterMs for as long as the update has not landed.

var remindAfterMs = 6 * 60 * 60 * 1000;

function due(alerts, shown, now, enabled) {
    if (!enabled || !alerts || alerts.length === 0)
        return null;
    var newest = alerts[0];
    if (!newest || !newest.commit)
        return null;
    var at = shown[newest.commit];
    if (at !== undefined && now - at < remindAfterMs)
        return null;
    return newest;
}

// prune drops the commits the box now runs, so an update leaves no state behind.
function prune(shown, alerts) {
    var keep = {};
    for (var i = 0; i < (alerts || []).length; i++) {
        var commit = alerts[i] && alerts[i].commit;
        if (commit && shown[commit] !== undefined)
            keep[commit] = shown[commit];
    }
    return keep;
}

// reasons lists what the alert says, newest first, at most max lines.
function reasons(alerts, max) {
    var out = [];
    for (var i = 0; i < (alerts || []).length && out.length < max; i++) {
        var text = (alerts[i] && (alerts[i].reason || alerts[i].subject)) || "";
        if (text !== "")
            out.push(text);
    }
    return out;
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { remindAfterMs, due, prune, reasons };
