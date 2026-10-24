.pragma library

// Pure gallery model. NixOS packages Karuma with the desktop rather than as a
// separate RyoStore receipt: the shipped manifest owns installed state.
function shippedCard(entry) {
    return {
        id: entry.id,
        name: entry.name || entry.id,
        desc: entry.description || entry.desc || "",
        installed: true,
        version: "",
        installedVersion: "",
        updateAvailable: false,
        unavailable: false,
        unavailableEdition: false,
        unavailableReason: "",
        requiredWindowManager: "",
        downloadPaused: false,
        resourceTier: entry.resourceTier || "",
        downloadPauseReason: ""
    };
}

function cardModel(shippedDesigns, catalogueDesigns) {
    const out = [];
    const seen = {};
    const shipped = Array.isArray(shippedDesigns) ? shippedDesigns : [];
    const catalogue = Array.isArray(catalogueDesigns) ? catalogueDesigns : [];

    for (let i = 0; i < shipped.length; i++) {
        const card = shippedCard(shipped[i]);
        if (!card.id || seen[card.id])
            continue;
        seen[card.id] = true;
        out.push(card);
    }

    for (let i = 0; i < catalogue.length; i++) {
        const item = catalogue[i];
        if (!item || !item.id)
            continue;

        const existingIndex = out.findIndex(entry => entry.id === item.id);
        if (existingIndex >= 0) {
            if (seen[item.id]) {
                // Store metadata may describe the card but must not revoke a
                // bar style shipped with the OS, even when its receipt is absent.
                const own = out[existingIndex];
                out[existingIndex] = Object.assign({}, item, {
                    id: own.id,
                    name: own.name,
                    desc: own.desc,
                    installed: true,
                    updateAvailable: false,
                    unavailable: false,
                    unavailableEdition: false,
                    unavailableReason: "",
                    requiredWindowManager: "",
                    downloadPaused: false,
                    downloadPauseReason: ""
                });
            } else {
                out[existingIndex] = item;
            }
        } else {
            out.push(item);
        }
    }
    return out;
}
