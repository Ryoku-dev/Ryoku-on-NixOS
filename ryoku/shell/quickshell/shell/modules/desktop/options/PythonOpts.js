.pragma library
// The Python faces keep their own options in the widget's <prefix>Opts slot of
// widgets.json: one JSON object per widget, read by PythonFaceWidget and pushed
// into the live face. Panels edit it through these helpers so every write is a
// whole-object replace (the adapter cannot see in-place key edits).

function read(Config, prefix) {
    const raw = Config[prefix + "Opts"];
    if (raw && typeof raw === "object")
        return raw;
    if (!raw || String(raw).length === 0)
        return {};
    try {
        const parsed = JSON.parse(String(raw));
        return (parsed && typeof parsed === "object") ? parsed : {};
    } catch (e) {
        return {};
    }
}

function put(Config, prefix, key, value) {
    const o = read(Config, prefix);
    if (o[key] === value)
        return;
    o[key] = value;
    Config.set(prefix + "Opts", JSON.stringify(o));
}

// One write for several keys: back-to-back set() calls interleave file writes
// with the watcher's reloads and a stale reload can undo the earlier key.
function putMany(Config, prefix, values) {
    const o = read(Config, prefix);
    let dirty = false;
    for (const key in values)
        if (o[key] !== values[key]) {
            o[key] = values[key];
            dirty = true;
        }
    if (dirty)
        Config.set(prefix + "Opts", JSON.stringify(o));
}
