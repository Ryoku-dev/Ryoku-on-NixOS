function classes(clients) {
    const seen = {};
    const result = [];
    for (const client of Array.isArray(clients) ? clients : []) {
        const className = client && typeof client.className === "string" ? client.className : "";
        if (className && !seen[className]) {
            seen[className] = true;
            result.push(className);
        }
    }
    return result;
}

function pin(pinned, className) {
    const result = Array.isArray(pinned) ? pinned.filter(value => typeof value === "string" && value) : [];
    return typeof className === "string" && className && !result.includes(className) ? result.concat(className) : result;
}

function unpin(pinned, className) {
    return (Array.isArray(pinned) ? pinned : []).filter(value => value !== className);
}

function resolve(pinned, activeClients) {
    const active = classes(activeClients);
    const configured = Array.isArray(pinned) ? pinned.filter(value => typeof value === "string" && value) : [];
    const result = [];
    for (const className of configured)
        if (!result.includes(className)) result.push(className);
    for (const className of active)
        if (!result.includes(className)) result.push(className);
    return result;
}

// A RyoStore dock's runtime root: the Dock.qml inside the view its docks.json
// row names, as a file URL. A malformed row, or one whose view is not its own
// (dock-views/<id>/<digest>), names nothing.
const STORE_VIEW = /^dock-views\/([a-z0-9]+(?:-[a-z0-9]+)*)\/[a-f0-9]{64}$/;

function storeDesignUrl(rows, id, stateRoot) {
    for (const row of Array.isArray(rows) ? rows : []) {
        const match = STORE_VIEW.exec(String(row && row.view || ""));
        if (row && row.id === id && match && match[1] === id && String(row.version || "") !== "")
            return "file://" + stateRoot + "/" + row.view + "/Dock.qml";
    }
    return "";
}

if (typeof module !== "undefined" && module.exports) module.exports = { pin, unpin, resolve, storeDesignUrl };
