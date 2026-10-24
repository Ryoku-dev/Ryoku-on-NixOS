// Provider window rows are already restricted to application toplevels. The
// foreign-toplevel handle is enrichment only: it can briefly be absent when a
// title changes because provider and protocol updates arrive independently.
// Presence must follow the provider row through that join gap or the wallpaper
// frost flashes off while the application window is still mapped.
function countOnActiveWorkspace(windows, workspaces, outputName) {
    var active = [];
    var output = String(outputName || "");
    var wsCount = workspaces ? workspaces.length : 0;
    for (var i = 0; i < wsCount; i++) {
        var workspace = workspaces[i];
        if (!workspace || workspace.is_active !== true)
            continue;
        if (output !== "" && workspace.output !== output)
            continue;
        active.push(workspace.id);
    }
    if (active.length === 0)
        return 0;

    var count = 0;
    var windowCount = windows ? windows.length : 0;
    for (var j = 0; j < windowCount; j++) {
        var window = windows[j];
        if (!window || active.indexOf(window.workspace) === -1)
            continue;
        if (window.toplevel && window.toplevel.minimized === true)
            continue;
        count++;
    }
    return count;
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { countOnActiveWorkspace };
