<<<<<<< port (unstable-dev)
const ids = ["iris", "gokko", "caelestia", "tansu", "python"];
=======
const ids = ["gokko", "caelestia", "tansu", "python", "imi"];
>>>>>>> upstream Ryoku 1.9.4 (8eac7f0)

function isStyle(id) {
    return ids.indexOf(String(id || "")) >= 0;
}

function visibleStyles(styles, onlySubshells) {
    const source = Array.isArray(styles) ? styles : [];
    return onlySubshells ? source.filter(style => isStyle(style.id)) : source;
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { isStyle, visibleStyles };
