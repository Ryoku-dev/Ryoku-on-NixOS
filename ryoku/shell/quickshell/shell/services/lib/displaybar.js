function styleFor(displays, output, fallback) {
    const styles = displays && displays.bar_style;
    const value = output && styles ? styles[output] : undefined;
    // iRiS supplies whole-desktop reservations and panels, not a single bar.
    // Until its complete desktop family is partitionable, keep it global-only.
    if (fallback === "iris") return "iris";
    if (value === "iris") return fallback;
    return typeof value === "string" && value.length > 0 ? value : fallback;
}

function widgetEnabled(displays, output, style, id, fallback) {
    const outputs = displays && displays.bar_widgets;
    const styles = output && outputs ? outputs[output] : undefined;
    const widgets = styles && style ? styles[style] : undefined;
    const value = widgets && id ? widgets[id] : undefined;
    return typeof value === "boolean" ? value : fallback;
}

// Whether any connected output requests the given style, including when that
// output's bar is hidden. The primary scene can then retain shared popups/IPC.
function hasStyle(displays, screens, fallback, target) {
    for (const screen of screens || []) {
        if (screen && screen.name && styleFor(displays, screen.name, fallback) === target)
            return true;
    }
    return false;
}
