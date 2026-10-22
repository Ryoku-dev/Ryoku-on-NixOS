// Keep the Quickshell wl_output screencopy context off niri until upstream fixes it.
function shouldUseGrim(setting, desktop, niriSocket) {
    if (setting === "1") return true;
    var desktops = String(desktop || "").toLowerCase().split(":");
    return desktops.indexOf("niri") !== -1 || !!niriSocket;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { shouldUseGrim };
}
