pragma Singleton

import QtQuick
import Quickshell
import inir.services
import inir.modules.common

// Icon-name resolution for the frame's own pieces. Ryoku owns the system
// icon theme (the daemon writes gsettings and the palette plane); this is
// the pure lookup the bubble icons need, without the reference's
// theme-writing side effects.
Singleton {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    // Smart icon resolution: preserve app-provided identity whenever possible.
    // Only repair the duplicated Electron resources path that is known-broken.
    function smartIconName(icon, appId) {
        if (!icon) {
            const guessed = AppSearch.lookupDesktopEntry(appId)?.icon ?? AppSearch.guessIcon(appId);
            return guessed || appId || "application-x-executable";
        }

        if (icon.startsWith("/") || icon.startsWith("file://")) {
            const path = icon.startsWith("file://") ? icon.substring(7) : icon;

            if (path.indexOf("/resources/app/resources/") !== -1) {
                return path.replace("/resources/app/resources/", "/resources/");
            }
        }

        return icon;
    }
}
