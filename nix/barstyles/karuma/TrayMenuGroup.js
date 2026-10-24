.pragma library

// Only one app tray menu may be open at a time, across every icon and every
// monitor's bar. A menu claims the slot when it opens; whichever menu held it
// is closed. This is a pragma library so the slot is shared by all instances.

var current = null;

function claim(menu) {
    const old = current;
    current = menu;
    if (old && old !== menu) {
        try { old.close(); } catch (e) { /* already destroyed */ }
    }
}

function release(menu) {
    if (current === menu) current = null;
}

function closeCurrent() {
    const old = current;
    current = null;
    if (old) {
        try { old.close(); } catch (e) { /* already destroyed */ }
    }
}
