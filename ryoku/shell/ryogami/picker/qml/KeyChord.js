function canon(trigger) {
    if (!trigger)
        return null;
    var text = String(trigger).toLowerCase().trim();
    if (text.indexOf("click") >= 0)
        return null;
    var parts = text.split("+");
    var ctrl = false, alt = false, shift = false, base = "";
    for (var i = 0; i < parts.length; ++i) {
        var part = parts[i];
        if (part === "ctrl" || part === "control") ctrl = true;
        else if (part === "alt") alt = true;
        else if (part === "shift") shift = true;
        else if (part) base = part;
    }
    if (base === "return")
        base = "enter";
    if (!base)
        return null;
    if (base.length === 1 && !/[a-z0-9]/.test(base) && !ctrl && !alt && !shift)
        return base;
    if (/^[0-9]$/.test(base) && !ctrl && !alt && !shift)
        return base;
    return (ctrl ? "ctrl+" : "") + (alt ? "alt+" : "") + (shift ? "shift+" : "") + base;
}

function signature(event) {
    var key = event.key;
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
    var alt = (event.modifiers & Qt.AltModifier) !== 0;
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0;
    var base = "";
    if (key >= Qt.Key_A && key <= Qt.Key_Z) {
        base = String.fromCharCode(key).toLowerCase();
    } else if (key >= Qt.Key_0 && key <= Qt.Key_9) {
        if (!ctrl && !alt)
            return String.fromCharCode(key);
        base = String.fromCharCode(key);
    } else {
        switch (key) {
        case Qt.Key_Left: base = "left"; break;
        case Qt.Key_Right: base = "right"; break;
        case Qt.Key_Up: base = "up"; break;
        case Qt.Key_Down: base = "down"; break;
        case Qt.Key_Tab: base = "tab"; break;
        case Qt.Key_Backtab: base = "tab"; shift = true; break;
        case Qt.Key_Return:
        case Qt.Key_Enter: base = "enter"; break;
        case Qt.Key_Space: base = "space"; break;
        default:
            var text = event.text;
            if (!ctrl && !alt && text && text.length === 1
                    && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127)
                return text;
            return "";
        }
    }
    return (ctrl ? "ctrl+" : "") + (alt ? "alt+" : "") + (shift ? "shift+" : "") + base;
}
