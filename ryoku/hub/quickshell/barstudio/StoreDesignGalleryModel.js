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

function toList(value) {
    if (Array.isArray(value)) return value;
    if (!value || !Number.isSafeInteger(value.length) || value.length < 0) return [];
    const result = [];
    for (let i = 0; i < value.length; i++) result.push(value[i]);
    return result;
}

function cardModel(shippedDesigns, catalogueDesigns) {
    const out = [];
    const seen = {};
    // QML QVariantList/sequence wrappers are array-like, but Array.isArray()
    // can return false. Preserve the shipped manifest rather than dropping it.
    const shipped = toList(shippedDesigns);
    const catalogue = toList(catalogueDesigns);

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

// The Hub's final bar gallery must include the NixOS-shipped Karuma even when
// an old Store catalogue or QML list conversion omits its registry entry.
// Keep this decision in the pure model so the actual rendered list is tested.
function galleryCards(category, shippedDesigns, catalogueDesigns) {
    const cards = cardModel(shippedDesigns, catalogueDesigns);
    if (category !== "barstyles") return cards;

    const karuma = shippedCard({
        id: "karuma", name: "Karuma", desc: "The default Ryoku Nix bar."
    });
    return [karuma].concat(cards.filter(card => card && card.id !== "karuma"));
}
