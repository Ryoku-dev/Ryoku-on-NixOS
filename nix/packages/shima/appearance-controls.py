#!/usr/bin/env python3

from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace(path, old, new):
    file = root / path
    source = file.read_text()
    if source.count(old) != 1:
        raise RuntimeError(f"Expected exactly one patch anchor in {path}: {old[:90]!r}")
    file.write_text(source.replace(old, new))


replace(
    "modules/common/Config.qml",
    'property string preset: "iris" // IrisStyle.presets:',
    'property string frontend: "inir" // Ryoku palette frontend, independent of iNiR presets\n                    property string preset: "iris" // IrisStyle.presets:',
)

replace(
    "modules/iris/settings/IrisThemes.qml",
    "import qs.modules.common\n",
    "import qs.modules.common\nimport qs.services\n",
)

replace(
    "modules/iris/settings/IrisThemes.qml",
    """    function choose(theme: var): void {
        if (root.coloursOnly) root.applyColours(theme)
        else root.apply(theme)
    }""",
    """    function choose(theme: var): void {
        if (!theme) return
        if (theme.id === "ryoku") {
            Config.setNestedValue("iris.appearance.frontend", "ryoku")
            return
        }
        if (root.coloursOnly) root.applyColours(theme)
        else root.apply(theme)
    }""",
)

replace(
    "modules/iris/settings/IrisThemes.qml",
    '        const v = root.resolved(theme?.values ?? {})',
    '        const v = root.resolved(theme?.values ?? {})\n        const ryoku = String(theme?.id ?? "") === "ryoku"',
)
replace(
    "modules/iris/settings/IrisThemes.qml",
    '            surface: IrisStyle.materialSwatch(String(v["iris.appearance.theme.surface"])),',
    '            surface: ryoku ? RyokuTokens.paper : IrisStyle.materialSwatch(String(v["iris.appearance.theme.surface"])),',
)
replace(
    "modules/iris/settings/IrisThemes.qml",
    '            accent: accent,\n            highlight: highlight,',
    '            accent: ryoku ? RyokuTokens.ink : accent,\n            highlight: ryoku ? RyokuTokens.inkDim : highlight,',
)
replace(
    "modules/iris/settings/IrisThemes.qml",
    '            glass: v["iris.appearance.glass.mode"] !== "off",',
    '            glass: ryoku ? IrisStyle.glassy : v["iris.appearance.glass.mode"] !== "off",',
)
replace(
    "modules/iris/settings/IrisThemes.qml",
    '''            description: "Ryoku's paper-and-ink palette adapted to Shima's upstream iRiS renderer.",''',
    '''            description: "Ryoku's live paper-and-ink frontend. Keeps your selected iNiR theme, including Liquid Glass.",''',
)

replace(
    "modules/iris/edit/IrisThemeCard.qml",
    "    readonly property bool current: IrisThemes.activeId === card.theme.id",
    """    readonly property bool current: card.theme.id === "ryoku"
        ? IrisStyle.ryokuFrontend : IrisThemes.activeId === card.theme.id""",
)
replace(
    "modules/iris/settings/IrisOptions.qml",
    'isOn: () => IrisThemes.activeId === theme.id && !IrisThemes.modified, run: () => IrisThemes.choose(theme)',
    'isOn: () => theme.id === "ryoku" ? IrisStyle.ryokuFrontend : IrisThemes.activeId === theme.id && !IrisThemes.modified, run: () => IrisThemes.choose(theme)',
)

replace(
    "modules/iris/settings/IrisOptions.qml",
    "import qs.modules.background.widgets\n",
    'import qs.modules.background.widgets\nimport "../../background/widgets/OrganicEdgeConfig.js" as EdgeConfig\n',
)

wave_options = """        { section: "frameMusic", group: "Wave colours", label: "Palette source", path: "background.edgeWidgets.organic.palette", kind: "choice", fallback: "theme", visibleWhen: "!iris.surround.music=frame", choices: EdgeConfig.palettes.map(p => ({label:p.name,value:p.value})), keywords: ["wave", "colour", "color", "palette", "music", "visualizer"] },
        { section: "frameMusic", group: "Wave colours", label: "Colour movement", path: "background.edgeWidgets.organic.colorMode", kind: "choice", fallback: "flow", visibleWhen: "!iris.surround.music=frame", choices: EdgeConfig.colorModes.map(p => ({label:p.name,value:p.value})) },
        { section: "frameMusic", group: "Wave colours", label: "Primary colour", path: "background.edgeWidgets.organic.primaryColor", kind: "text", fallback: "#b5a0ff", placeholder: "#b5a0ff", visibleWhen: "background.edgeWidgets.organic.palette=custom" },
        { section: "frameMusic", group: "Wave colours", label: "Secondary colour", path: "background.edgeWidgets.organic.secondaryColor", kind: "text", fallback: "#64dbcf", placeholder: "#64dbcf", visibleWhen: "background.edgeWidgets.organic.palette=custom" },
        { section: "frameMusic", group: "Wave colours", label: "Tertiary colour", path: "background.edgeWidgets.organic.tertiaryColor", kind: "text", fallback: "#ffb2cf", placeholder: "#ffb2cf", visibleWhen: "background.edgeWidgets.organic.palette=custom" },
        { section: "frameMusic", group: "Wave colours", label: "Full colour editor", kind: "action", button: "Open Organic Edge colours", run: () => GlobalStates.openSettingsPage(14, "Organic edge"), visibleWhen: "!iris.surround.music=frame" },
"""
replace(
    "modules/iris/settings/IrisOptions.qml",
    '        { section: "frameMusic", group: "Frame response", label: "Edges",',
    wave_options + '        { section: "frameMusic", group: "Frame response", label: "Edges",',
)

replace(
    "modules/iris/settings/IrisOptions.qml",
    '{label:"Wallpaper",value:"wallpaper",get swatch() { return IrisStyle.wallpaperLight }}] },',
    '{label:"Wallpaper",value:"wallpaper",get swatch() { return IrisStyle.wallpaperLight }},{label:"Custom",value:"custom"}] },',
)

replace(
    "modules/iris/settings/IrisOptions.qml",
    '        { section: "frameMusic", group: "Finish", label: "Light",',
    '        { section: "frameMusic", group: "Finish", label: "Custom frame colour", path: "iris.surround.musicCustomColour", kind: "text", fallback: "#e6e1da", placeholder: "#e6e1da", visibleWhen: "iris.surround.musicColour=custom", showIf: () => ["frame", "both"].includes(String(Config.options?.iris?.surround?.music ?? "widget")) },\n        { section: "frameMusic", group: "Finish", label: "Light",',
)

replace(
    "modules/common/Config.qml",
    'property string musicColour: "pearl" // "pearl" | "accent" | "highlight" | "wallpaper"',
    'property string musicColour: "pearl" // "pearl" | "accent" | "highlight" | "wallpaper" | "custom"\n                    property string musicCustomColour: "#e6e1da"',
)

replace(
    "modules/iris/frame/IrisFrame.qml",
    '''        return colour === "accent" ? IrisStyle.accent''',
    '''        if (colour === "custom") {
            const picked = Qt.color(String(root.surround?.musicCustomColour ?? "#e6e1da"))
            return picked.valid ? picked : IrisStyle.text
        }
        return colour === "accent" ? IrisStyle.accent''',
)


replace(
    "modules/iris/bar/IrisBar.qml",
    '''                IrisThemes.apply(found)
                return found.name
            }
            case "colours": {''',
    '''                if (found.id === "ryoku") IrisThemes.choose(found)
                else IrisThemes.apply(found)
                return found.name
            }
            case "colours": {''',
)
