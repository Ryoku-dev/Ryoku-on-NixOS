// Snapshot sections have independent lifetimes. Preserve unchanged array/object
// identities so QML does not rebuild workspace and output consumers on focus.
function applyFrame(target, frame) {
    const defaults = {
        ready: false,
        caps: {},
        workspaceModel: "fixed",
        focusedOutput: "",
        outputs: [],
        configFiles: [],
        keyboardLayout: "",
        keyboardLayouts: [],
        windows: [],
        workspaces: [],
        overviewOpen: false
    };

    const sections = {
        ready: ["ready", "caps", "workspaceModel", "configFiles"],
        focus: ["focusedOutput"],
        outputs: ["outputs"],
        windows: ["windows"],
        workspaces: ["workspaces"],
        keyboard: ["keyboardLayout", "keyboardLayouts"],
        overview: ["overviewOpen"]
    };

    const incoming = frame.versions;
    const previous = target.versions;

    // Compatibility with a daemon from before section versions existed:
    // compare values and preserve object identity where nothing moved.
    if (!incoming || typeof incoming !== "object") {
        for (const key of Object.keys(defaults)) {
            const value = frame[key] === undefined ? defaults[key] : frame[key];
            if (JSON.stringify(target[key]) !== JSON.stringify(value))
                target[key] = value;
        }
        if (target.versions !== null)
            target.versions = null;
        return;
    }

    // First versioned snapshot must seed every section.
    if (!previous || typeof previous !== "object") {
        for (const key of Object.keys(defaults))
            target[key] = frame[key] === undefined ? defaults[key] : frame[key];
        target.versions = incoming;
        return;
    }

    // Afterwards trust the daemon's section counters. A window event no longer
    // serialises and compares every output/workspace/capability tree in QML.
    for (const section of Object.keys(sections)) {
        if (incoming[section] === previous[section])
            continue;

        for (const key of sections[section])
            target[key] = frame[key] === undefined ? defaults[key] : frame[key];
    }

    target.versions = incoming;
}

function workspaceRows(residue, sets, dynamic) {
    if (dynamic) {
        return residue.map(w => ({
            id: String(w.id), name: String(w.name), output: w.output || "",
            active: w.active === true, windows: Number(w.windows || 0),
            occupied: Number(w.windows || 0) > 0, fullscreen: w.fullscreen === true,
            special: w.special === true, layout: w.layout || ""
        }));
    }
    const byName = {};
    for (const w of residue) byName[w.name] = w;
    return Array.from(sets).map(s => {
        const w = byName[s.name] || {};
        return {
            id: String(w.id || s.name), name: s.name, output: w.output || "",
            active: s.active === true, urgent: s.urgent === true,
            canActivate: s.canActivate === true, windows: Number(w.windows || 0),
            occupied: Number(w.windows || 0) > 0, fullscreen: w.fullscreen === true,
            special: w.special === true, layout: w.layout || ""
        };
    });
}
