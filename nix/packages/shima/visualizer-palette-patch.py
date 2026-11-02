#!/usr/bin/env python3

from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace(path, old, new):
    file = root / path
    content = file.read_text()
    if content.count(old) != 1:
        raise RuntimeError(f"Missing or ambiguous anchor in {path}: {old[:90]!r}")
    file.write_text(content.replace(old, new))

(root / "services/RyokuVisualizerPalette.qml").write_text(Path(sys.argv[2]).read_text())
with (root / "services/qmldir").open("a") as qmldir:
    qmldir.write("\nsingleton RyokuVisualizerPalette 1.0 RyokuVisualizerPalette.qml\n")

cava = "services/CavaTheme.qml"
file = root / cava
source = file.read_text()
start = source.index('    readonly property var themeColors: [')
end = source.index("\n    // Vibrant", start)
source = source[:start] + "    readonly property var themeColors: RyokuVisualizerPalette.themeColors\n" + source[end:]
source = source.replace(
    '''        : root.colorSource === "cover"
            ? root.coverColors
            : root.themeColors''',
    '''        : root.colorSource === "cover"
            ? root.coverColors
            : RyokuVisualizerPalette.cavaColors''')
source = source.replace(
    "root._visualColor(Appearance.colors.colSecondary,",
    "root._visualColor(RyokuVisualizerPalette.themeColors[1],"
).replace(
    "root._visualColor(Appearance.colors.colPrimary,",
    "root._visualColor(RyokuVisualizerPalette.themeColors[0],"
).replace(
    "root._visualColor(Appearance.colors.colTertiary,",
    "root._visualColor(RyokuVisualizerPalette.themeColors[2],"
)
file.write_text(source)

replace(
    "modules/background/widgets/OrganicEdgeConfig.js",
    'var palettes = [',
    'var palettes = [\n    {name: "Cava (Matugen)", value: "cava"},',
)

replace(
    "modules/background/widgets/OrganicEdgeWidget.qml",
    '''            : root.palette === "theme"
                ? [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary]
                : root.palette === "adaptive" ? root.adaptivePalette : root.wallpaperPalette''',
    '''            : root.palette === "theme" ? RyokuVisualizerPalette.themeColors
                : root.palette === "cava" ? RyokuVisualizerPalette.cavaColors
                : root.palette === "adaptive" ? root.adaptivePalette : root.wallpaperPalette''',
)

replace(
    "modules/iris/settings/IrisOptions.qml",
    '''run: () => GlobalStates.openSettingsPage(14, "Organic edge")''',
    '''run: () => Quickshell.execDetached([Quickshell.shellPath("scripts/inir"), "ipc", "settingsNav", "section", "14", "Organic edge"])''',
)

replace(
    "modules/iris/settings/IrisOptions.qml",
    '''{label:"Wallpaper",value:"wallpaper",get swatch() { return IrisStyle.wallpaperLight }},{label:"Custom",value:"custom"}] },''',
    '''{label:"Wallpaper",value:"wallpaper",get swatch() { return IrisStyle.wallpaperLight }},{label:"Matugen",value:"theme",get swatch() { return RyokuVisualizerPalette.themeColors[0] }},{label:"Cava",value:"cava",get swatch() { return RyokuVisualizerPalette.cavaColors[0] }},{label:"Custom",value:"custom"}] },''',
)

replace(
    "modules/iris/frame/IrisFrame.qml",
    '''        return colour === "accent" ? IrisStyle.accent''',
    '''        if (colour === "theme") return RyokuVisualizerPalette.themeColors[0]
        if (colour === "cava") {
            const colors = RyokuVisualizerPalette.cavaColors
            return colors[Math.floor(colors.length / 2)]
        }
        return colour === "accent" ? IrisStyle.accent''',
)

replace(
    "modules/background/Background.qml",
    """        function organicEdgeState(): string {""",
    """        function ryokuVisualizerPaletteState(): string {
            const hex = colors => colors.map(color => color.toString())
            return JSON.stringify({
                theme: hex(RyokuVisualizerPalette.themeColors),
                cava: hex(RyokuVisualizerPalette.cavaColors),
                media: hex(CavaTheme.visualizerColors),
                colorSource: CavaTheme.colorSource
            })
        }

        function organicEdgeState(): string {""",
)
