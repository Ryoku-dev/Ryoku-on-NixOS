// A RyoStore product the shell runs in place: the entry file inside the view
// its <category>.json row names, as a file URL. A malformed row, a row without
// a version, or one whose view is not its own (<viewRoot>/<id>/<digest>) names
// nothing, so the host draws its shipped design instead.
const VIEW = /^([a-z]+(?:-[a-z]+)*-views)\/([a-z0-9]+(?:-[a-z0-9]+)*)\/[a-f0-9]{64}$/;
const ENTRY = /^[A-Za-z][A-Za-z0-9]*\.qml$/;

function storeViewUrl(rows, id, stateRoot, viewRoot, entry) {
    if (!ENTRY.test(String(entry || "")))
        return "";
    for (const row of Array.isArray(rows) ? rows : []) {
        const match = VIEW.exec(String(row && row.view || ""));
        if (row && row.id === id && match && match[1] === viewRoot && match[2] === id
                && String(row.version || "") !== "")
            return "file://" + stateRoot + "/" + row.view + "/" + entry;
    }
    return "";
}

if (typeof module !== "undefined" && module.exports) module.exports = { storeViewUrl };
