pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "InkMath.js" as InkMath
import "KarumaSchema.js" as Schema

/*
 * Karuma's palette + type bridge for Ryoku (the paper-and-ink look follows the original Ma design).
 *
 * Colours follow Ricelin's resolution chain exactly (its Dyn singleton):
 *   named themePalette (~/.config/ryoku/shell.json)
 *     -> live Matugen palette (~/.cache/ryoku/colors.json, only while
 *        ~/.config/ryoku/theme.json does not say followWallpaper=false)
 *     -> built-in washi/ink fallback.
 * Every file is watched, so a wallpaper / Matugen change retints the bar live.
 *
 * Karuma's "paper and four inks" ramp (upstream core/Ink.qml) is derived from
 * the resolved surface + on-surface colours, so contrast stays right on any
 * generated palette. Red ("you" / "now") is the Matugen primary, exactly as
 * Ricelin's pill uses it; "needs you" states (muted, low battery, offline) use
 * Matugen's error role.
 *
 * Bundled fonts include: Fraunces (clock, titles), Space Grotesk (values),
 * Yuji Boku (every kanji) and your monospace for small labels.
 */
Item {
    id: root

    // ------------------------------------------------------------ sources
    property var wall: ({})
    property var named: null
    property bool followWallpaper: true
    // The style file, read and written through KarumaConfig; `style` is its raw object.
    readonly property var config: cfg
    readonly property var style: cfg.raw

    readonly property string cacheRoot: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string configRoot: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string colorsPath: cacheRoot + "/ryoku/colors.json"
    readonly property string shellConfigPath: configRoot + "/ryoku/shell.json"
    readonly property string themeJsonPath: configRoot + "/ryoku/theme.json"
    readonly property string stylePath: configRoot + "/karuma/style.json"

    function lowerKeys(obj) {
        const out = {};
        if (obj && typeof obj === "object") {
            for (const k in obj)
                out[String(k).toLowerCase()] = obj[k];
        }
        return out;
    }

    function parseObject(text) {
        try {
            const value = JSON.parse(text || "");
            return (value && typeof value === "object" && !Array.isArray(value)) ? lowerKeys(value) : {};
        } catch (e) {
            return {};
        }
    }

    function parseNamed(text) {
        const obj = parseObject(text);
        return (obj && obj.themepalette && typeof obj.themepalette === "object")
            ? lowerKeys(obj.themepalette) : null;
    }

    function parseFollow(text) {
        try {
            const obj = JSON.parse(text || "");
            return (obj && typeof obj.followWallpaper === "boolean") ? obj.followWallpaper : true;
        } catch (e) {
            return true;
        }
    }

    function valid(value) {
        return typeof value === "string" && /^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(value);
    }

    // Accepts Matugen snake_case and camelCase role names.
    function pick(source, keys, fallback) {
        if (source) {
            for (let i = 0; i < keys.length; ++i) {
                const value = source[String(keys[i]).toLowerCase()];
                if (valid(value))
                    return value;
            }
        }
        return fallback;
    }

    function resolve(keys, fallback) {
        let value = pick(root.named, keys, null);
        if (!value && root.followWallpaper)
            value = pick(root.wall, keys, null);
        return value || fallback;
    }

    // ------------------------------------------------------------ resolved roles
    readonly property string bgHex: resolve(["surface", "background"], "#1c1713")
    readonly property string fgHex: resolve(["on_surface", "onsurface", "foreground", "fg", "color7"], "#f0e5d3")
    readonly property string sealHex: resolve(["primary", "color1", "red"], "#c74637")
    readonly property string onSealHex: resolve(["on_primary", "onprimary"], bgHex)
    readonly property string urgentHex: resolve(["error", "color9"], "#ff6b5e")
    readonly property string highHex: resolve(["surface_container_highest", "surfacecontainerhighest", "surface_container_high"], "#352c25")

    readonly property var ramp: InkMath.ramp(fgHex, bgHex)

    // The page every part of the bar is printed on.
    readonly property color paper: bgHex
    readonly property color paperHigh: highHex
    readonly property color ink: ramp.ink
    readonly property color inkDim: ramp.inkDim
    readonly property color inkMuted: ramp.inkMuted
    readonly property color inkFaint: ramp.inkFaint
    // Red means "you" or "now": the seal, the now-notch, stamps.
    readonly property color seal: sealHex
    readonly property color onSeal: onSealHex
    // ...and "needs you": muted, low battery, offline.
    readonly property color urgent: urgentHex
    // Inversion plates: the selected thing turns into solid ink.
    readonly property color bone: fgHex
    readonly property color boneInk: bgHex
    readonly property color line: alpha(fgHex, 0.22)
    readonly property color lineSoft: alpha(fgHex, 0.10)
    readonly property color lineStrong: alpha(fgHex, 0.40)
    readonly property bool light: InkMath.isLight(bgHex)

    // Day and music progress follow Matugen's accent rather than the neutral ink
    // ramp: the fill is `primary`, the now-notch / playhead is `tertiary`, and the
    // track and hour ticks are tints of the same hue. Without a Matugen palette
    // they fall back to the seal colour.
    readonly property string progressHex: resolve(["primary"], sealHex)
    readonly property string progressNowHex: resolve(["tertiary", "secondary"], progressHex)
    readonly property color progress: progressHex
    readonly property color progressSoft: alpha(progressHex, 0.78)
    readonly property color progressTrack: alpha(progressHex, 0.20)
    readonly property color progressHairline: alpha(progressHex, 0.45)
    readonly property color progressTick: alpha(progressHex, 0.65)
    readonly property color progressTickDim: alpha(progressHex, 0.30)
    readonly property color progressNow: progressNowHex

    // Names the pop-out sheets (and PaperButton) were already written with.
    readonly property color mutedInk: inkMuted
    readonly property color hairline: lineStrong
    readonly property color vermilion: seal
    readonly property color onVermilion: onSeal

    // ------------------------------------------------------------ pop-up design tokens
    // One vocabulary for every sheet, menu and tile, all derived from the roles
    // above so a Matugen change retints them with the rest of the bar.
    //   paper       the sheet itself            raised   a card sitting on the paper
    //   hover/press interactive fills            line     the sheet's edge
    //   seal tint   "on" tiles and focus rings   shadow   the soft lift under a sheet
    readonly property color raised: alpha(fgHex, light ? 0.045 : 0.05)
    readonly property color hover: alpha(fgHex, light ? 0.075 : 0.075)
    readonly property color press: alpha(fgHex, light ? 0.13 : 0.12)
    readonly property color sealTint: alpha(sealHex, light ? 0.13 : 0.17)
    readonly property color sealEdge: alpha(sealHex, 0.55)
    readonly property real shadowAlpha: light ? 0.16 : 0.38
    // Corner radii: sheet, control/tile, small chip.
    readonly property real radiusL: 14
    readonly property real radiusM: 10
    readonly property real radiusS: 6

    function alpha(c, a) {
        const col = Qt.color(String(c));
        return Qt.rgba(col.r, col.g, col.b, a);
    }

    // ------------------------------------------------------------ style (optional)
    // ~/.config/karuma/style.json is normalised by KarumaSchema. It includes
    // four-edge geometry, Strip/Islands, surface curvature/borders, three lanes,
    // per-module treatment/scale/padding/opacity, typography overrides, progress
    // presentation, fullscreen/reserve behaviour, clock/date and quick controls.
    // Unknown keys are preserved by KarumaConfig for forward compatibility.
    readonly property string hours: String(style.hours || "12h")
    readonly property int barHeight: conf.height
    readonly property real typeScale: ({ small: 0.9, regular: 1, large: 1.15 })[String(style.typeSize || "regular")] || 1
    readonly property bool allIndicators: String(style.indicators || "all") !== "active"
    readonly property bool still: String(style.motion || "paper") === "still"
    // Everything that moves asks this, so the Animations switch reaches the whole bar,
    // its pop-ups and the hub at once. Off means every change lands immediately.
    readonly property bool animate: !still
    readonly property string sealGlyph: String(style.sealGlyph || "力").slice(0, 2)

    // ------------------------------------------------------------ Karuma
    // Appearance, spacing and modules (KarumaSchema owns defaults and ranges).
    readonly property var conf: cfg.conf
    // How the workspaces are drawn (kanji, numbers, roman, dashes, dots). The hub
    // writes this key through the same KarumaConfig instance the bar reads.
    readonly property string workspaceStyle: conf.workspaceStyle
    readonly property real barOpacity: conf.opacity
    readonly property string layoutMode: conf.layout
    readonly property bool islands: layoutMode === "islands"
    readonly property string edge: conf.edge
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property string align: conf.align
    readonly property int lengthPercent: conf.length
    readonly property int railWidth: conf.railWidth
    readonly property int cornerRadius: conf.cornerRadius
    readonly property int innerRadiusBias: conf.innerRadiusBias
    readonly property real borderWidth: conf.borderWidth
    readonly property real borderOpacity: conf.borderOpacity
    // Gaps and rounded shapes only mean something once the bar floats; a
    // full-width bar is always edge to edge and square.
    readonly property bool floating: conf.floating
    readonly property string shape: (floating || islands) ? conf.shape : "square"
    readonly property int gapTop: floating ? conf.gap.top : 0
    readonly property int gapBottom: floating ? conf.gap.bottom : 0
    readonly property int gapLeft: floating ? conf.gap.left : 0
    readonly property int gapRight: floating ? conf.gap.right : 0
    // Three explicit lanes are the Karuma layout contract. Strings only change when
    // placement changes, so opacity/spacing slider drags never rebuild the rows.
    readonly property string leftKey: Schema.zones(conf).left.join(",")
    readonly property string centerKey: Schema.zones(conf).center.join(",")
    readonly property string rightKey: Schema.zones(conf).right.join(",")
    readonly property int moduleGap: conf.moduleGap
    readonly property int islandPad: conf.islandPad
    readonly property int islandGap: conf.islandGap
    readonly property real laneSpread: conf.laneSpread
    readonly property real textScale: conf.textScale
    readonly property real iconScale: conf.iconScale
    function moduleStyle(id) { return Schema.styleFor(conf, id) }
    function moduleOptions(id) { return Schema.moduleOptions(conf, id) }
    function moduleScale(id) { return moduleOptions(id).scale }
    function modulePadding(id) { return moduleOptions(id).padding }
    function moduleOpacity(id) { return moduleOptions(id).opacity }
    function moduleVisible(id) { return conf.hidden.indexOf(String(id)) < 0 }

    // Global bar size: the legacy typeSize steps times the hub's continuous scale.
    // The strip's height, its icons, its text and its spacing all derive from this
    // one number, so they grow together.
    readonly property real sizeScale: typeScale * conf.scale
    // Clock and date: each can be hidden alone; the date is a Qt pattern (a "|"
    // stacks it on two lines). The hours key above is the existing 12/24 switch.
    readonly property bool showTime: conf.showClock
    readonly property bool showDate: conf.showDate
    readonly property string dateFormat: conf.dateFormat
    // The thin line under the strip: "disabled", "daily" or "music".
    readonly property string indicatorMode: conf.indicator
    readonly property string progressStyle: conf.progressStyle
    readonly property string progressPlacement: conf.progressPlacement
    readonly property int progressThickness: conf.progressThickness
    readonly property real progressOpacity: conf.progressOpacity
    readonly property string fullscreenMode: conf.fullscreenMode
    readonly property bool reserveSpace: conf.reserveSpace
    // Quick settings controls the user turned off (ids, comma separated).
    readonly property string quickHiddenKey: conf.quickHidden.join(",")

    // ------------------------------------------------------------ fonts
    FontLoader { id: frauncesFont; source: Qt.resolvedUrl("assets/fonts/Fraunces.ttf") }
    FontLoader { id: frauncesItalicFont; source: Qt.resolvedUrl("assets/fonts/Fraunces-Italic.ttf") }
    FontLoader { id: groteskFont; source: Qt.resolvedUrl("assets/fonts/SpaceGrotesk.ttf") }
    FontLoader { id: brushFont; source: Qt.resolvedUrl("assets/fonts/YujiBoku.ttf") }

    // Fraunces upright and italic ship as two files that share one family name.
    property var systemFamilies: Qt.fontFamilies()
    function preferredFont(requested, fallback) {
        const name = String(requested || "")
        return name.length && systemFamilies.indexOf(name) >= 0 ? name : fallback
    }
    readonly property string bundledDisplay: frauncesFont.status === FontLoader.Ready ? frauncesFont.name
        : (frauncesItalicFont.status === FontLoader.Ready ? frauncesItalicFont.name : "serif")
    readonly property string bundledText: groteskFont.status === FontLoader.Ready ? groteskFont.name : "sans-serif"
    readonly property string bundledJp: brushFont.status === FontLoader.Ready ? brushFont.name : "Noto Serif CJK JP"
    readonly property string display: preferredFont(style.displayFont, bundledDisplay)
    readonly property string text: preferredFont(style.textFont, bundledText)
    readonly property string jp: preferredFont(style.jpFont, bundledJp)
    readonly property string mono: {
        const want = [String(style.monoFont || ""), "JetBrainsMono Nerd Font", "JetBrains Mono", "Berkeley Mono",
                      "Iosevka", "Fira Code", "Cascadia Mono", "DejaVu Sans Mono"];
        for (let i = 0; i < want.length; ++i)
            if (want[i].length && systemFamilies.indexOf(want[i]) >= 0)
                return want[i];
        return "monospace";
    }

    // Fraunces is variable: optical size follows the size it is set at, and
    // the weight must be given on the axis as well as font.weight.
    function axes(size, wght) {
        return { "opsz": Math.max(9, Math.min(144, size)), "wght": wght === undefined ? 400 : wght };
    }
    readonly property var valueAxes: ({ "wght": 500 })

    // ------------------------------------------------------------ files
    FileView {
        id: paletteFile
        path: root.colorsPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wall = root.parseObject(paletteFile.text())
    }

    FileView {
        id: shellFile
        path: root.shellConfigPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.named = root.parseNamed(shellFile.text())
    }

    FileView {
        id: themeFile
        path: root.themeJsonPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.followWallpaper = root.parseFollow(themeFile.text())
    }

    KarumaConfig { id: cfg; path: root.stylePath }
}
