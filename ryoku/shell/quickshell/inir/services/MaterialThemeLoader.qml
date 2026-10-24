pragma Singleton
pragma ComponentBehavior: Bound

import inir.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Reads the palette the wallpaper daemon publishes and feeds it to
 * Appearance.m3colors, so the family is always dressed in what the desktop
 * wears. Generation and external-app fan-out belong to Ryoku's matugen
 * plane; this is the frame's read side only.
 */
Singleton {
    id: root
    property string filePath: Directories.generatedMaterialThemePath
    property bool ready: false

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    function colorToHex(c: color): string {
        return "#" + ((1 << 24) | (Math.round(c.r * 255) << 16) | Math.round(c.g * 255) << 8 | Math.round(c.b * 255)).toString(16).slice(1)
    }

    function reapplyTheme(): void {
        themeFileView.reload()
    }

    function applyColors(fileContent): void {
        if (!fileContent || fileContent.trim().length === 0) {
            _log("[MaterialThemeLoader] keeping defaults — empty palette file")
            return
        }

        let json
        try {
            json = JSON.parse(fileContent)
        } catch (e) {
            _log("[MaterialThemeLoader] palette file unreadable:", e)
            return
        }

        if (!json || typeof json !== "object" || !json.background) {
            _log("[MaterialThemeLoader] invalid palette structure (no background key)")
            return
        }

        _log("[MaterialThemeLoader] Applying", Object.keys(json).length, "color keys")
        for (const key in json) {
            if (json.hasOwnProperty(key)) {
                const camelCaseKey = key.replace(/_([a-z])/g, (g) => g[1].toUpperCase())
                const noPrefix = camelCaseKey.startsWith("term") || camelCaseKey === "darkmode" || camelCaseKey === "transparent"
                const m3Key = noPrefix ? camelCaseKey : `m3${camelCaseKey}`
                if (Appearance.m3colors[m3Key] === undefined)
                    continue
                Appearance.m3colors[m3Key] = json[key]
            }
        }

        if (typeof json.darkmode === "boolean") {
            Appearance.m3colors.darkmode = json.darkmode
        } else if (typeof json.darkmode === "string") {
            Appearance.m3colors.darkmode = json.darkmode === "true"
        } else {
            Appearance.m3colors.darkmode = (Appearance.m3colors.m3background.hslLightness < 0.5)
        }
        _log("[MaterialThemeLoader] Colors applied, darkmode:", Appearance.m3colors.darkmode)
    }

    FileView {
        id: themeFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onLoadedChanged: {
            root.applyColors(themeFileView.text())
            root.ready = true
        }
        onLoadFailed: root._log("[MaterialThemeLoader] palette file not present yet")
    }
}
