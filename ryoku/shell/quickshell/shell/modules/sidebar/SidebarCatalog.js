.pragma library

const catalog = [];


function byId(id) {
    for (var i = 0; i < catalog.length; ++i) {
        if (catalog[i].id === id)
            return catalog[i];
    }
    return null;
}
