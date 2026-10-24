pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import QtQuick
import stage.modules.common
import stage.modules.common.functions
import Ryoku.Ui.Singletons

Singleton {
    id: root

    readonly property string currentScheme: Config.options.background.widgets.colorScheme ?? "default"

    // Widget faces need the wallpaper's Material roles, not Stage's translucent
    // paper-and-ink compatibility tints. Fixed roles use their closest opaque
    // Stage alias; the regular roles resolve directly from the live palette.
    readonly property QtObject m3colors: QtObject {
        readonly property bool darkmode: !Tokens.light
        readonly property color m3background: Tokens.role("background", Tokens.paper)
        readonly property color m3onBackground: Tokens.role("onBackground", Tokens.ink)
        readonly property color m3surface: Tokens.role("surface", Tokens.paper)
        readonly property color m3surfaceDim: Tokens.role("surfaceDim", Tokens.paper)
        readonly property color m3surfaceBright: Tokens.role("surfaceBright", Tokens.paperLift)
        readonly property color m3surfaceContainerLowest: Tokens.role("surfaceContainerLowest", Tokens.paper)
        readonly property color m3surfaceContainerLow: Tokens.role("surfaceContainerLow", Tokens.paperLift)
        readonly property color m3surfaceContainer: Tokens.role("surfaceContainer", Tokens.paperLift)
        readonly property color m3surfaceContainerHigh: Tokens.role("surfaceContainerHigh", Tokens.paperLift)
        readonly property color m3surfaceContainerHighest: Tokens.role("surfaceContainerHighest", Qt.tint(Tokens.paper, Tokens.tint10))
        readonly property color m3onSurface: Tokens.role("onSurface", Tokens.ink)
        readonly property color m3surfaceVariant: Tokens.role("surfaceVariant", Tokens.paperLift)
        readonly property color m3onSurfaceVariant: Tokens.role("onSurfaceVariant", Tokens.inkDim)
        readonly property color m3inverseSurface: Tokens.role("inverseSurface", Tokens.bone)
        readonly property color m3inverseOnSurface: Tokens.role("inverseOnSurface", Tokens.inkOnBone)
        readonly property color m3outline: Tokens.role("outline", Qt.tint(Tokens.paper, Tokens.inkMuted))
        readonly property color m3outlineVariant: Tokens.role("outlineVariant", Qt.tint(Tokens.paper, Tokens.inkFaint))
        readonly property color m3shadow: Tokens.role("shadow", Tokens.paper)
        readonly property color m3scrim: Tokens.role("scrim", Tokens.ink)
        readonly property color m3surfaceTint: Tokens.role("surfaceTint", Tokens.ink)
        readonly property color m3primary: Tokens.role("primary", Tokens.sun)
        readonly property color m3onPrimary: Tokens.role("onPrimary", Tokens.paper)
        readonly property color m3primaryContainer: Tokens.role("primaryContainer", Qt.tint(Tokens.paper, Tokens.tint16))
        readonly property color m3onPrimaryContainer: Tokens.role("onPrimaryContainer", Tokens.ink)
        readonly property color m3inversePrimary: Tokens.role("inversePrimary", Tokens.sun)
        readonly property color m3secondary: Tokens.role("secondary", Tokens.bone)
        readonly property color m3onSecondary: Tokens.role("onSecondary", Tokens.inkOnBone)
        readonly property color m3secondaryContainer: Tokens.role("secondaryContainer", Tokens.bone)
        readonly property color m3onSecondaryContainer: Tokens.role("onSecondaryContainer", Tokens.inkOnBone)
        readonly property color m3tertiary: Tokens.role("tertiary", Tokens.inkDim)
        readonly property color m3onTertiary: Tokens.role("onTertiary", Tokens.paper)
        readonly property color m3tertiaryContainer: Tokens.role("tertiaryContainer", Qt.tint(Tokens.paper, Tokens.tint16))
        readonly property color m3onTertiaryContainer: Tokens.role("onTertiaryContainer", Tokens.ink)
        readonly property color m3error: Tokens.role("error", Tokens.alert)
        readonly property color m3onError: Tokens.role("onError", Tokens.paper)
        readonly property color m3errorContainer: Tokens.role("errorContainer", Qt.tint(Tokens.paper, Tokens.tint16))
        readonly property color m3onErrorContainer: Tokens.role("onErrorContainer", Tokens.ink)

        // Material fixed roles retain Stage's light-stock/dark-content pairing,
        // matching the fixed tone-90/tone-80 and tone-10/tone-30 ordering.
        readonly property color m3primaryFixed: Tokens.role("primaryFixed", Tokens.bone)
        readonly property color m3primaryFixedDim: Tokens.role("primaryFixedDim", Tokens.inkDim)
        readonly property color m3onPrimaryFixed: Tokens.role("onPrimaryFixed", Tokens.inkOnBone)
        readonly property color m3onPrimaryFixedVariant: Tokens.role("onPrimaryFixedVariant", Qt.tint(Tokens.paper, Tokens.inkOnBoneDim))
        readonly property color m3secondaryFixed: Tokens.role("secondaryFixed", Tokens.bone)
        readonly property color m3secondaryFixedDim: Tokens.role("secondaryFixedDim", Tokens.inkDim)
        readonly property color m3onSecondaryFixed: Tokens.role("onSecondaryFixed", Tokens.inkOnBone)
        readonly property color m3onSecondaryFixedVariant: Tokens.role("onSecondaryFixedVariant", Qt.tint(Tokens.paper, Tokens.inkOnBoneDim))
        readonly property color m3tertiaryFixed: Tokens.role("tertiaryFixed", Tokens.bone)
        readonly property color m3tertiaryFixedDim: Tokens.role("tertiaryFixedDim", Tokens.inkDim)
        readonly property color m3onTertiaryFixed: Tokens.role("onTertiaryFixed", Tokens.inkOnBone)
        readonly property color m3onTertiaryFixedVariant: Tokens.role("onTertiaryFixedVariant", Qt.tint(Tokens.paper, Tokens.inkOnBoneDim))

        // Stage's semantic success aliases cover palettes without this family;
        // the translucent container fallback is composited over paper.
        readonly property color m3success: Tokens.role("success", Tokens.ink)
        readonly property color m3onSuccess: Tokens.role("onSuccess", Tokens.paper)
        readonly property color m3successContainer: Tokens.role("successContainer", Qt.tint(Tokens.paper, Tokens.tint16))
        readonly property color m3onSuccessContainer: Tokens.role("onSuccessContainer", Tokens.ink)
    }

    readonly property QtObject colors: QtObject {
        readonly property color colSubtext: root.m3colors.m3outline

        readonly property color colLayer0Base: ColorUtils.mix(root.m3colors.m3background, root.m3colors.m3primary,
            Config.options.appearance.extraBackgroundTint ? 0.99 : 1)
        readonly property color colLayer0: ColorUtils.transparentize(colLayer0Base, 0)
        readonly property color colOnLayer0: root.m3colors.m3onBackground
        readonly property color colLayer0Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.9), 0)
        readonly property color colLayer0Active: ColorUtils.transparentize(ColorUtils.mix(colLayer0, colOnLayer0, 0.8), 0)
        readonly property color colLayer0Border: ColorUtils.mix(root.m3colors.m3outlineVariant, colLayer0, 0.4)

        readonly property color colLayer1Base: root.m3colors.m3surfaceContainerLow
        readonly property color colLayer1: ColorUtils.solveOverlayColor(colLayer0Base, colLayer1Base, 1)
        readonly property color colOnLayer1: root.m3colors.m3onSurfaceVariant
        readonly property color colOnLayer1Inactive: ColorUtils.mix(colOnLayer1, colLayer1, 0.45)
        readonly property color colLayer1Hover: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.92), 0)
        readonly property color colLayer1Active: ColorUtils.transparentize(ColorUtils.mix(colLayer1, colOnLayer1, 0.85), 0)

        readonly property color colLayer2Base: root.m3colors.m3surfaceContainer
        readonly property color colLayer2: ColorUtils.solveOverlayColor(colLayer1Base, colLayer2Base, 1)
        readonly property color colLayer2Hover: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.90), 1)
        readonly property color colLayer2Active: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, colOnLayer2, 0.80), 1)
        readonly property color colLayer2Disabled: ColorUtils.solveOverlayColor(colLayer1Base, ColorUtils.mix(colLayer2Base, root.m3colors.m3background, 0.8), 1)
        readonly property color colOnLayer2: root.m3colors.m3onSurface
        readonly property color colOnLayer2Disabled: ColorUtils.mix(colOnLayer2, root.m3colors.m3background, 0.4)

        readonly property color colLayer3Base: root.m3colors.m3surfaceContainerHigh
        readonly property color colLayer3: ColorUtils.solveOverlayColor(colLayer2Base, colLayer3Base, 1)
        readonly property color colLayer3Hover: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.90), 1)
        readonly property color colLayer3Active: ColorUtils.solveOverlayColor(colLayer2Base, ColorUtils.mix(colLayer3Base, colOnLayer3, 0.80), 1)
        readonly property color colOnLayer3: root.m3colors.m3onSurface

        readonly property color colLayer4Base: root.m3colors.m3surfaceContainerHighest
        readonly property color colLayer4: ColorUtils.solveOverlayColor(colLayer3Base, colLayer4Base, 1)
        readonly property color colLayer4Hover: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.90), 1)
        readonly property color colLayer4Active: ColorUtils.solveOverlayColor(colLayer3Base, ColorUtils.mix(colLayer4Base, colOnLayer4, 0.80), 1)
        readonly property color colOnLayer4: root.m3colors.m3onSurface

        readonly property color colPrimary: root.m3colors.m3primary
        readonly property color colOnPrimary: root.m3colors.m3onPrimary
        readonly property color colPrimaryHover: ColorUtils.mix(colPrimary, colLayer1Hover, 0.87)
        readonly property color colPrimaryActive: ColorUtils.mix(colPrimary, colLayer1Active, 0.7)
        readonly property color colPrimaryContainer: root.m3colors.m3primaryContainer
        readonly property color colPrimaryContainerHover: ColorUtils.mix(colPrimaryContainer, colOnPrimaryContainer, 0.9)
        readonly property color colPrimaryContainerActive: ColorUtils.mix(colPrimaryContainer, colOnPrimaryContainer, 0.8)
        readonly property color colOnPrimaryContainer: root.m3colors.m3onPrimaryContainer

        readonly property color colSecondary: root.m3colors.m3secondary
        readonly property color colSecondaryHover: ColorUtils.mix(colSecondary, colLayer1Hover, 0.85)
        readonly property color colSecondaryActive: ColorUtils.mix(colSecondary, colLayer1Active, 0.4)
        readonly property color colOnSecondary: root.m3colors.m3onSecondary
        readonly property color colSecondaryContainer: root.m3colors.m3secondaryContainer
        readonly property color colSecondaryContainerHover: ColorUtils.mix(colSecondaryContainer, colOnSecondaryContainer, 0.90)
        readonly property color colSecondaryContainerActive: ColorUtils.mix(colSecondaryContainer, colOnSecondaryContainer, 0.54)
        readonly property color colOnSecondaryContainer: root.m3colors.m3onSecondaryContainer
        readonly property color colSecondaryOnContainer: colOnSecondaryContainer

        readonly property color colTertiary: root.m3colors.m3tertiary
        readonly property color colTertiaryHover: ColorUtils.mix(colTertiary, colLayer1Hover, 0.85)
        readonly property color colTertiaryActive: ColorUtils.mix(colTertiary, colLayer1Active, 0.4)
        readonly property color colTertiaryContainer: root.m3colors.m3tertiaryContainer
        readonly property color colTertiaryContainerHover: ColorUtils.mix(colTertiaryContainer, colOnTertiaryContainer, 0.90)
        readonly property color colTertiaryContainerActive: ColorUtils.mix(colTertiaryContainer, colLayer1Active, 0.54)
        readonly property color colOnTertiary: root.m3colors.m3onTertiary
        readonly property color colOnTertiaryContainer: root.m3colors.m3onTertiaryContainer

        readonly property color colBackgroundSurfaceContainer: ColorUtils.transparentize(root.m3colors.m3surfaceContainer, 0)
        readonly property color colBackgroundSurfaceContainerAccent: ColorUtils.transparentize(
            ColorUtils.mix(root.m3colors.m3surfaceContainer, root.m3colors.m3primaryContainer,
                1.0 - (Config.options.search.appearance.accentPanels ? Config.options.search.appearance.accentStrength : 0.0)), 0)
        readonly property color colSurfaceContainerLow: ColorUtils.solveOverlayColor(root.m3colors.m3background, root.m3colors.m3surfaceContainerLow, 1)
        readonly property color colSurfaceContainer: ColorUtils.solveOverlayColor(root.m3colors.m3surfaceContainerLow, root.m3colors.m3surfaceContainer, 1)
        readonly property color colSurfaceContainerHigh: ColorUtils.solveOverlayColor(root.m3colors.m3surfaceContainer, root.m3colors.m3surfaceContainerHigh, 1)
        readonly property color colSurfaceContainerHighest: ColorUtils.solveOverlayColor(root.m3colors.m3surfaceContainerHigh, root.m3colors.m3surfaceContainerHighest, 1)
        readonly property color colSurfaceContainerHighestHover: ColorUtils.mix(root.m3colors.m3surfaceContainerHighest, root.m3colors.m3onSurface, 0.95)
        readonly property color colSurfaceContainerHighestActive: ColorUtils.mix(root.m3colors.m3surfaceContainerHighest, root.m3colors.m3onSurface, 0.85)
        readonly property color colOnSurface: root.m3colors.m3onSurface
        readonly property color colOnSurfaceVariant: root.m3colors.m3onSurfaceVariant

        readonly property color colTooltip: root.m3colors.m3surfaceContainerHigh
        readonly property color colOnTooltip: root.m3colors.m3onSurface
        readonly property color colScrim: ColorUtils.transparentize(root.m3colors.m3scrim, 0.5)
        readonly property color colShadow: ColorUtils.transparentize(root.m3colors.m3shadow, 0.7)
        readonly property color colOutline: root.m3colors.m3outline
        readonly property color colOutlineVariant: root.m3colors.m3outlineVariant
        readonly property color colError: root.m3colors.m3error
        readonly property color colErrorHover: ColorUtils.mix(root.m3colors.m3error, colLayer1Hover, 0.85)
        readonly property color colErrorActive: ColorUtils.mix(root.m3colors.m3error, colLayer1Active, 0.7)
        readonly property color colOnError: root.m3colors.m3onError
        readonly property color colErrorContainer: root.m3colors.m3errorContainer
        readonly property color colErrorContainerHover: ColorUtils.mix(root.m3colors.m3errorContainer, root.m3colors.m3onErrorContainer, 0.90)
        readonly property color colErrorContainerActive: ColorUtils.mix(root.m3colors.m3errorContainer, root.m3colors.m3onErrorContainer, 0.70)
        readonly property color colOnErrorContainer: root.m3colors.m3onErrorContainer
    }

    readonly property real backgroundTintOpacity: {
        if (!(Config.options.background.widgets.tintOpacityEnabled ?? false))
            return 1;
        const value = Config.options.background.widgets.tintOpacity ?? 0.55;
        return Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.55;
    }

    // Apply at the background paint site, after selecting the palette/album
    // color. Keep raw palette tokens opaque: clocks also use them for hands,
    // digits and masks. Multiplication preserves any existing surface alpha.
    function tintBackground(background: color): color {
        if (root.backgroundTintOpacity === 1)
            return background;
        return Qt.rgba(background.r, background.g, background.b,
            background.a * root.backgroundTintOpacity);
    }

    // Material 3 Color Schemes for Background Widgets.
    //
    // Names are plain values; colours are getters into _schemeTable(), so a
    // reader still binds to the palette but this map itself does not. Built
    // eagerly with every colour inline, it re-evaluated on each palette role
    // change — 22 times per frame of a preset's palette crossfade — and took
    // every reader with it, while the only reader wants the names.
    readonly property var schemeNames: ({
        "default": Translation.tr("Default Surface"),
        "expressive_primary": Translation.tr("Expressive Primary"),
        "expressive_secondary": Translation.tr("Expressive Secondary"),
        "expressive_tertiary": Translation.tr("Expressive Tertiary"),
        "hero_primary": Translation.tr("Hero Primary"),
        "vibrant_mix": Translation.tr("Vibrant Mix"),
        "muted_surface": Translation.tr("Muted Low Surface"),
        "secondary_fixed": Translation.tr("Secondary Fixed"),
        "tertiary_showcase": Translation.tr("Tertiary Showcase"),
        "error_alert": Translation.tr("Error Alert"),
        "inverse_surface": Translation.tr("Inverse Surface"),
        "tri_blend": Translation.tr("Tri-Color Blend")
    })
    readonly property var schemes: {
        const result = {};
        const fields = ["accentColor", "cardBgColor", "highlightCircleColor", "highlightTextColor", "innerShapeColor", "onAccentColor", "outlineColor", "pillBgColor", "pillFillColor", "subtextColorOnBg", "successColor", "surfaceVariantColor", "textColorOnBg", "textColorOnPillFill", "textColorOnPillTrack", "warningColor"];
        for (const key in root.schemeNames) {
            const entry = { "name": root.schemeNames[key] };
            for (const field of fields) {
                Object.defineProperty(entry, field, {
                    enumerable: true,
                    get: () => root._schemeTable()[key][field]
                });
            }
            result[key] = entry;
        }
        return result;
    }

    function _alpha(value, opacity) {
        const color = Qt.color(value);
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    function _schemeTable() {
        const c = root.colors;
        const m = root.m3colors;
        const mix = ColorUtils.mix;
        return ({
            "default": {
                "name": Translation.tr("Default Surface"),
                "cardBgColor": c.colSurfaceContainerHigh,
                "textColorOnBg": c.colOnSurfaceVariant,
                "accentColor": c.colPrimary,
                "onAccentColor": c.colOnPrimary,
                "pillBgColor": c.colSurfaceContainerHighest,
                "pillFillColor": c.colSecondaryContainer,
                "textColorOnPillFill": c.colOnSecondaryContainer,
                "textColorOnPillTrack": c.colOnSurface,
                "subtextColorOnBg": root._alpha(c.colOnSurfaceVariant, 0.6),
                "innerShapeColor": c.colSurfaceContainerHighest,
                "highlightCircleColor": c.colOnSurfaceVariant,
                "highlightTextColor": c.colSurfaceContainerHigh,
                "successColor": m.m3success,
                "warningColor": c.colError,
                "outlineColor": c.colOutline,
                "surfaceVariantColor": m.m3surfaceVariant
            },
            "expressive_primary": {
                "name": Translation.tr("Expressive Primary"),
                "cardBgColor": c.colPrimaryContainer,
                "textColorOnBg": c.colOnPrimaryContainer,
                "accentColor": c.colPrimary,
                "onAccentColor": c.colOnPrimary,
                "pillBgColor": mix(c.colPrimary, c.colPrimaryContainer, 0.25),
                "pillFillColor": c.colPrimary,
                "textColorOnPillFill": c.colOnPrimary,
                "textColorOnPillTrack": c.colOnPrimaryContainer,
                "subtextColorOnBg": root._alpha(c.colOnPrimaryContainer, 0.7),
                "innerShapeColor": mix(c.colPrimary, c.colPrimaryContainer, 0.35),
                "highlightCircleColor": c.colPrimary,
                "highlightTextColor": c.colOnPrimary,
                "successColor": c.colTertiary,
                "warningColor": mix(c.colError, c.colPrimary, 0.3),
                "outlineColor": c.colPrimaryContainer,
                "surfaceVariantColor": mix(c.colPrimaryContainer, c.colSurfaceContainerHigh, 0.5)
            },
            "expressive_secondary": {
                "name": Translation.tr("Expressive Secondary"),
                "cardBgColor": c.colSecondaryContainer,
                "textColorOnBg": c.colOnSecondaryContainer,
                "accentColor": c.colSecondary,
                "onAccentColor": c.colOnSecondary,
                "pillBgColor": mix(c.colSecondary, c.colSecondaryContainer, 0.25),
                "pillFillColor": c.colSecondary,
                "textColorOnPillFill": c.colOnSecondary,
                "textColorOnPillTrack": c.colOnSecondaryContainer,
                "subtextColorOnBg": root._alpha(c.colOnSecondaryContainer, 0.7),
                "innerShapeColor": mix(c.colSecondary, c.colSecondaryContainer, 0.35),
                "highlightCircleColor": c.colSecondary,
                "highlightTextColor": c.colOnSecondary,
                "successColor": c.colPrimary,
                "warningColor": mix(c.colError, c.colSecondary, 0.3),
                "outlineColor": c.colSecondaryContainer,
                "surfaceVariantColor": mix(c.colSecondaryContainer, c.colSurfaceContainerHigh, 0.5)
            },
            "expressive_tertiary": {
                "name": Translation.tr("Expressive Tertiary"),
                "cardBgColor": c.colTertiaryContainer,
                "textColorOnBg": c.colOnTertiaryContainer,
                "accentColor": c.colTertiary,
                "onAccentColor": c.colOnTertiary,
                "pillBgColor": mix(c.colTertiary, c.colTertiaryContainer, 0.25),
                "pillFillColor": c.colTertiary,
                "textColorOnPillFill": c.colOnTertiary,
                "textColorOnPillTrack": c.colOnTertiaryContainer,
                "subtextColorOnBg": root._alpha(c.colOnTertiaryContainer, 0.7),
                "innerShapeColor": mix(c.colTertiary, c.colTertiaryContainer, 0.35),
                "highlightCircleColor": c.colTertiary,
                "highlightTextColor": c.colOnTertiary,
                "successColor": m.m3successContainer,
                "warningColor": mix(c.colError, c.colTertiary, 0.3),
                "outlineColor": c.colTertiaryContainer,
                "surfaceVariantColor": mix(c.colTertiaryContainer, c.colSurfaceContainerHigh, 0.5)
            },
            "hero_primary": {
                "name": Translation.tr("Hero Primary"),
                "cardBgColor": c.colPrimary,
                "textColorOnBg": c.colOnPrimary,
                "accentColor": c.colPrimaryContainer,
                "onAccentColor": c.colOnPrimaryContainer,
                "pillBgColor": mix(c.colOnPrimary, c.colPrimary, 0.2),
                "pillFillColor": c.colPrimaryContainer,
                "textColorOnPillFill": c.colOnPrimaryContainer,
                "textColorOnPillTrack": c.colOnPrimary,
                "subtextColorOnBg": root._alpha(c.colOnPrimary, 0.75),
                "innerShapeColor": mix(c.colOnPrimary, c.colPrimary, 0.25),
                "highlightCircleColor": c.colOnPrimary,
                "highlightTextColor": c.colPrimary,
                "successColor": c.colSecondaryContainer,
                "warningColor": c.colErrorContainer,
                "outlineColor": mix(c.colPrimary, c.colOnPrimary, 0.4),
                "surfaceVariantColor": mix(c.colPrimary, c.colOnPrimary, 0.2)
            },
            "vibrant_mix": {
                "name": Translation.tr("Vibrant Mix"),
                "cardBgColor": mix(c.colPrimaryContainer, c.colTertiaryContainer, 0.4),
                "textColorOnBg": c.colOnPrimaryContainer,
                "accentColor": c.colTertiary,
                "onAccentColor": c.colOnTertiary,
                "pillBgColor": mix(c.colPrimary, c.colTertiaryContainer, 0.3),
                "pillFillColor": c.colTertiary,
                "textColorOnPillFill": c.colOnTertiary,
                "textColorOnPillTrack": c.colOnPrimaryContainer,
                "subtextColorOnBg": root._alpha(c.colOnPrimaryContainer, 0.7),
                "innerShapeColor": mix(c.colPrimaryContainer, c.colTertiaryContainer, 0.6),
                "highlightCircleColor": c.colTertiary,
                "highlightTextColor": c.colOnTertiary,
                "successColor": c.colPrimary,
                "warningColor": mix(c.colError, c.colTertiary, 0.4),
                "outlineColor": mix(c.colPrimaryContainer, c.colTertiaryContainer, 0.5),
                "surfaceVariantColor": mix(c.colPrimary, c.colTertiaryContainer, 0.2)
            },
            "muted_surface": {
                "name": Translation.tr("Muted Low Surface"),
                "cardBgColor": c.colSurfaceContainerLow,
                "textColorOnBg": c.colOnSurface,
                "accentColor": c.colSecondary,
                "onAccentColor": c.colOnSecondary,
                "pillBgColor": c.colSurfaceContainerHigh,
                "pillFillColor": c.colSecondaryContainer,
                "textColorOnPillFill": c.colOnSecondaryContainer,
                "textColorOnPillTrack": c.colOnSurface,
                "subtextColorOnBg": root._alpha(c.colOnSurface, 0.6),
                "innerShapeColor": c.colSurfaceContainer,
                "highlightCircleColor": c.colSecondary,
                "highlightTextColor": c.colOnSecondary,
                "successColor": c.colTertiary,
                "warningColor": c.colError,
                "outlineColor": c.colOutline,
                "surfaceVariantColor": m.m3surfaceVariant
            },
            "secondary_fixed": {
                "name": Translation.tr("Secondary Fixed"),
                "cardBgColor": m.m3secondaryFixed,
                "textColorOnBg": m.m3onSecondaryFixed,
                "accentColor": c.colSecondary,
                "onAccentColor": c.colOnSecondary,
                "pillBgColor": mix(m.m3secondaryFixed, c.colSecondary, 0.25),
                "pillFillColor": c.colSecondaryContainer,
                "textColorOnPillFill": c.colOnSecondaryContainer,
                "textColorOnPillTrack": m.m3onSecondaryFixed,
                "subtextColorOnBg": root._alpha(m.m3onSecondaryFixed, 0.65),
                "innerShapeColor": mix(m.m3secondaryFixed, c.colSecondary, 0.3),
                "highlightCircleColor": c.colSecondary,
                "highlightTextColor": m.m3onSecondaryFixed,
                "successColor": m.m3success,
                "warningColor": mix(c.colError, c.colSecondary, 0.2),
                "outlineColor": m.m3onSecondaryFixedVariant,
                "surfaceVariantColor": mix(m.m3secondaryFixed, m.m3onSecondaryFixed, 0.15)
            },
            "tertiary_showcase": {
                "name": Translation.tr("Tertiary Showcase"),
                "cardBgColor": c.colTertiaryContainer,
                "textColorOnBg": c.colOnTertiaryContainer,
                "accentColor": c.colTertiary,
                "onAccentColor": c.colOnTertiary,
                "pillBgColor": mix(c.colTertiary, c.colTertiaryContainer, 0.2),
                "pillFillColor": c.colPrimary,
                "textColorOnPillFill": c.colOnPrimary,
                "textColorOnPillTrack": c.colOnTertiaryContainer,
                "subtextColorOnBg": root._alpha(c.colOnTertiaryContainer, 0.65),
                "innerShapeColor": mix(c.colTertiary, c.colTertiaryContainer, 0.3),
                "highlightCircleColor": c.colPrimary,
                "highlightTextColor": c.colOnPrimary,
                "successColor": c.colSecondary,
                "warningColor": mix(c.colError, c.colPrimary, 0.25),
                "outlineColor": mix(c.colTertiary, c.colTertiaryContainer, 0.4),
                "surfaceVariantColor": mix(c.colPrimary, c.colTertiaryContainer, 0.2)
            },
            "error_alert": {
                "name": Translation.tr("Error Alert"),
                "cardBgColor": c.colErrorContainer,
                "textColorOnBg": c.colOnErrorContainer,
                "accentColor": c.colError,
                "onAccentColor": c.colOnError,
                "pillBgColor": mix(c.colError, c.colErrorContainer, 0.25),
                "pillFillColor": c.colError,
                "textColorOnPillFill": c.colOnError,
                "textColorOnPillTrack": c.colOnErrorContainer,
                "subtextColorOnBg": root._alpha(c.colOnErrorContainer, 0.65),
                "innerShapeColor": mix(c.colError, c.colErrorContainer, 0.35),
                "highlightCircleColor": c.colError,
                "highlightTextColor": c.colOnError,
                "successColor": m.m3success,
                "warningColor": mix(c.colError, m.m3onErrorContainer, 0.5),
                "outlineColor": mix(c.colError, c.colErrorContainer, 0.5),
                "surfaceVariantColor": mix(c.colError, c.colErrorContainer, 0.2)
            },
            "inverse_surface": {
                "name": Translation.tr("Inverse Surface"),
                "cardBgColor": m.m3inverseSurface,
                "textColorOnBg": m.m3inverseOnSurface,
                "accentColor": m.m3inversePrimary,
                "onAccentColor": m.m3inverseOnSurface,
                "pillBgColor": mix(m.m3inverseSurface, m.m3inversePrimary, 0.3),
                "pillFillColor": m.m3inversePrimary,
                "textColorOnPillFill": m.m3inverseOnSurface,
                "textColorOnPillTrack": m.m3inverseOnSurface,
                "subtextColorOnBg": root._alpha(m.m3inverseOnSurface, 0.6),
                "innerShapeColor": mix(m.m3inverseSurface, m.m3inverseOnSurface, 0.2),
                "highlightCircleColor": m.m3inversePrimary,
                "highlightTextColor": m.m3inverseOnSurface,
                "successColor": mix(m.m3success, m.m3inverseSurface, 0.3),
                "warningColor": mix(c.colError, m.m3inversePrimary, 0.3),
                "outlineColor": mix(m.m3inverseOnSurface, m.m3inverseSurface, 0.4),
                "surfaceVariantColor": mix(m.m3inverseSurface, m.m3inverseOnSurface, 0.15)
            },
            "tri_blend": {
                "name": Translation.tr("Tri-Color Blend"),
                "cardBgColor": c.colSurfaceContainerHigh,
                "textColorOnBg": c.colOnPrimaryContainer,
                "accentColor": c.colSecondary,
                "onAccentColor": c.colOnSecondary,
                "pillBgColor": mix(c.colSecondary, c.colTertiaryContainer, 0.35),
                "pillFillColor": c.colTertiary,
                "textColorOnPillFill": c.colOnTertiary,
                "textColorOnPillTrack": c.colOnPrimaryContainer,
                "subtextColorOnBg": root._alpha(c.colOnPrimaryContainer, 0.6),
                "innerShapeColor": mix(c.colPrimary, c.colTertiaryContainer, 0.25),
                "highlightCircleColor": c.colTertiary,
                "highlightTextColor": c.colOnTertiary,
                "successColor": c.colPrimary,
                "warningColor": mix(c.colError, c.colSecondary, 0.4),
                "outlineColor": mix(c.colPrimary, c.colSecondary, 0.5),
                "surfaceVariantColor": mix(c.colPrimaryContainer, c.colTertiaryContainer, 0.3)
            }
        });
    }

    // One scheme's colour by name, for readers that pick a scheme of their own
    // (a face's expressive switch, the Customize scheme chips) instead of
    // following the global one.
    function _pick(scheme, field) {
        const table = root._schemeTable();
        return (table[scheme] ?? table.default)[field];
    }
    function getCardBgColor(scheme) { return root._pick(scheme, "cardBgColor"); }
    function getTextColorOnBg(scheme) { return root._pick(scheme, "textColorOnBg"); }
    function getSubtextColorOnBg(scheme) { return root._pick(scheme, "subtextColorOnBg"); }
    function getAccentColor(scheme) { return root._pick(scheme, "accentColor"); }
    function getPillBgColor(scheme) { return root._pick(scheme, "pillBgColor"); }
    function getInnerShapeColor(scheme) { return root._pick(scheme, "innerShapeColor"); }

    readonly property var currentColors: {
        const table = root._schemeTable();
        return table[root.currentScheme] ?? table.default;
    }

    readonly property color cardBgColor: currentColors.cardBgColor
    readonly property color textColorOnBg: currentColors.textColorOnBg
    readonly property color accentColor: currentColors.accentColor
    readonly property color onAccentColor: currentColors.onAccentColor
    readonly property color pillBgColor: currentColors.pillBgColor
    readonly property color pillFillColor: currentColors.pillFillColor
    readonly property color textColorOnPillFill: currentColors.textColorOnPillFill
    readonly property color textColorOnPillTrack: currentColors.textColorOnPillTrack
    readonly property color subtextColorOnBg: currentColors.subtextColorOnBg
    readonly property color innerShapeColor: currentColors.innerShapeColor
    readonly property color highlightCircleColor: currentColors.highlightCircleColor
    readonly property color highlightTextColor: currentColors.highlightTextColor
    readonly property color successColor: currentColors.successColor
    readonly property color warningColor: currentColors.warningColor
    readonly property color outlineColor: currentColors.outlineColor
    readonly property color surfaceVariantColor: currentColors.surfaceVariantColor

    // Key list for iteration in settings
    readonly property list<string> availableSchemes: [
        "default",
        "expressive_primary",
        "expressive_secondary",
        "expressive_tertiary",
        "hero_primary",
        "vibrant_mix",
        "muted_surface",
        "secondary_fixed",
        "tertiary_showcase",
        "error_alert",
        "inverse_surface",
        "tri_blend"
    ]
}
