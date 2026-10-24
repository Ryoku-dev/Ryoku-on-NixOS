pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import stage.modules.common
import stage.services

// One matugen preview pass serves the whole wallpaper-scheme gallery. The
// palette stays in memory: Stage neither owns nor shadows Ryoku's live colour
// files, and changing the image, mode, or source slot invalidates the one result.
Singleton {
    id: root

    property int consumers: 0
    property var wallpaperPreviews: ({})
    property string generatedFor: ""
    property string requestedFor: ""
    property bool generatingWallpaperPreviews: false

    readonly property bool wallpaperPreviewsReady:
        Object.keys(root.wallpaperPreviews).length > 0

    signal wallpaperPreviewsGenerationFailed()

    function acquire() {
        root.consumers++;
        root.ensureWallpaperPreviews();
    }

    function relinquish() {
        if (root.consumers <= 0)
            return;
        root.consumers--;
        if (root.consumers === 0) {
            previewDelay.stop();
            previewProcess.running = false;
            root.generatingWallpaperPreviews = false;
            root.generatedFor = "";
            root.requestedFor = "";
            root.wallpaperPreviews = ({});
        }
    }

    function wallpaperPreview(scheme) {
        const entry = root.wallpaperPreviews[String(scheme)];
        if (!entry)
            return null;
        return {
            primary: entry.primary || "transparent",
            secondary: entry.primary_container || entry.secondary || "transparent",
            tertiary: entry.tertiary || entry.secondary || "transparent"
        };
    }

    function previewMode() {
        return Appearance.m3colors.darkmode ? "dark" : "light";
    }

    function requestKey() {
        return [
            root.previewMode(),
            String(MaterialThemeLoader.sourceColorIndex),
            Wallpapers.effectiveWallpaperPath
        ].join("|");
    }

    function invalidate() {
        root.wallpaperPreviews = ({});
        root.generatedFor = "";
        if (root.consumers > 0)
            previewDelay.restart();
    }

    function ensureWallpaperPreviews() {
        if (root.consumers === 0)
            return false;
        const wallpaper = String(Wallpapers.effectiveWallpaperPath || "");
        if (wallpaper === "")
            return false;

        const key = root.requestKey();
        root.requestedFor = key;
        if (root.generatedFor === key && root.wallpaperPreviewsReady)
            return true;
        if (root.generatingWallpaperPreviews)
            return true;

        root.generatingWallpaperPreviews = true;
        previewProcess.generationKey = key;
        previewProcess.command = [
            Directories.extractColorsScriptPath,
            "--path", wallpaper,
            "--mode", root.previewMode(),
            "--index", String(MaterialThemeLoader.sourceColorIndex),
            "--all-previews", "-"
        ];
        previewProcess.running = true;
        return true;
    }

    Timer {
        id: previewDelay
        interval: 80
        repeat: false
        onTriggered: root.ensureWallpaperPreviews()
    }

    Connections {
        target: Wallpapers
        function onEffectiveWallpaperPathChanged() { root.invalidate(); }
    }

    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() { root.invalidate(); }
    }

    Connections {
        target: MaterialThemeLoader
        function onSourceColorIndexChanged() { root.invalidate(); }
    }

    Process {
        id: previewProcess
        property string generationKey: ""
        stdout: StdioCollector { id: previewOutput }
        stderr: StdioCollector { id: previewError }

        onExited: (exitCode, exitStatus) => {
            root.generatingWallpaperPreviews = false;
            if (exitCode === 0) {
                try {
                    const document = JSON.parse(String(previewOutput.text || "{}"));
                    root.wallpaperPreviews = document && typeof document === "object"
                        ? document : ({});
                    root.generatedFor = previewProcess.generationKey;
                } catch (error) {
                    root.wallpaperPreviews = ({});
                    root.wallpaperPreviewsGenerationFailed();
                }
            } else {
                const detail = String(previewError.text || "").trim();
                if (detail !== "")
                    console.warn("[ThemePreviewCache]", detail);
                root.wallpaperPreviewsGenerationFailed();
            }

            if (root.consumers > 0 && root.requestedFor !== previewProcess.generationKey)
                previewDelay.restart();
        }
    }
}
