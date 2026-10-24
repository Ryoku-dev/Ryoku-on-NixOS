// Stage keeps the island's compatibility names, but every value resolves
// through Ryoku's shared paper-and-ink token system.
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import stage.modules.common.functions
import stage.services
import Ryoku.Ui.Singletons


Singleton {
    id: root
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject sizes
    property string syntaxHighlightingTheme

    function withAlpha(value, alpha) {
        return Qt.rgba(value.r, value.g, value.b, alpha);
    }

    readonly property int windowRounding: {
        let rv = Config.options.appearance.roundingValue;
        if (rv <= 0)
            return 0;
        return Math.round(18 * rv / 24.0);
    }
    // Transparency. The quadratic functions were derived from analysis of hand-picked transparency values.
    ColorQuantizer {
        id: wallColorQuant
        property string wallpaperPath: Config.options?.background?.wallpaperPath ?? ""
        property bool wallpaperIsVideo: wallpaperPath !== "" && (wallpaperPath.endsWith(".mp4") || wallpaperPath.endsWith(".webm") || wallpaperPath.endsWith(".mkv") || wallpaperPath.endsWith(".avi") || wallpaperPath.endsWith(".mov"))
        source: wallpaperPath !== "" ? Qt.resolvedUrl(wallpaperIsVideo ? Config.options?.background?.thumbnailPath ?? "" : wallpaperPath) : ""
        depth: 0 // 2^0 = 1 color
        rescaleSize: 10
    }
    property real wallpaperVibrancy: (wallColorQuant.colors[0]?.hslSaturation + wallColorQuant.colors[0]?.hslLightness) / 2
    property real autoBackgroundTransparency: { // y = 0.5768x^2 - 0.759x + 0.2896
        let x = wallpaperVibrancy;
        let y = 0.5768 * (x * x) - 0.759 * (x) + 0.2896;
        return Math.max(0, Math.min(0.22, y)) - 0.12 * (m3colors.darkmode ? 0 : 1);
    }
    property real autoContentTransparency: 0.9
    property real backgroundTransparency: Config?.options.appearance.transparency.enable ? Config?.options.appearance.transparency.automatic ? autoBackgroundTransparency : Config?.options.appearance.transparency.backgroundTransparency : 0
    property real contentTransparency: Config?.options.appearance.transparency.enable ? (Config?.options.appearance.transparency.automatic ? autoContentTransparency : Config?.options.appearance.transparency.contentTransparency) : 0

    // The island expects Material role names. They are compatibility aliases,
    // not a second palette: each one points at the closest Ryoku token.
    m3colors: QtObject {
        property bool darkmode: !Tokens.light
        property bool transparent: false
        property color m3background: Tokens.paper
        property color m3onBackground: Tokens.ink
        property color m3surface: Tokens.paper
        property color m3surfaceDim: Tokens.paper
        property color m3surfaceBright: Tokens.paperLift
        property color m3surfaceContainerLowest: Tokens.paper
        property color m3surfaceContainerLow: Tokens.paperLift
        property color m3surfaceContainer: Tokens.paperLift
        property color m3surfaceContainerHigh: Tokens.paperLift
        property color m3surfaceContainerHighest: Tokens.tint10
        property color m3onSurface: Tokens.ink
        property color m3surfaceVariant: Tokens.paperLift
        property color m3onSurfaceVariant: Tokens.inkDim
        property color m3inverseSurface: Tokens.bone
        property color m3inverseOnSurface: Tokens.inkOnBone
        property color m3outline: Tokens.inkMuted
        property color m3outlineVariant: Tokens.inkFaint
        property color m3shadow: Tokens.paper
        property color m3scrim: Tokens.ink
        property color m3surfaceTint: Tokens.ink
        property color m3primary: Tokens.sun
        property color m3onPrimary: Tokens.paper
        property color m3primaryContainer: Tokens.tint16
        property color m3onPrimaryContainer: Tokens.ink
        property color m3inversePrimary: Tokens.sun
        property color m3secondary: Tokens.bone
        property color m3onSecondary: Tokens.inkOnBone
        property color m3secondaryContainer: Tokens.bone
        property color m3onSecondaryContainer: Tokens.inkOnBone
        property color m3tertiary: Tokens.inkDim
        property color m3onTertiary: Tokens.paper
        property color m3tertiaryContainer: Tokens.tint16
        property color m3onTertiaryContainer: Tokens.ink
        property color m3error: Tokens.alert
        property color m3onError: Tokens.paper
        property color m3errorContainer: Tokens.tint16
        property color m3onErrorContainer: Tokens.ink
        property color m3primaryFixed: Tokens.bone
        property color m3primaryFixedDim: Tokens.inkDim
        property color m3onPrimaryFixed: Tokens.inkOnBone
        property color m3onPrimaryFixedVariant: Tokens.inkOnBoneDim
        property color m3secondaryFixed: Tokens.bone
        property color m3secondaryFixedDim: Tokens.inkDim
        property color m3onSecondaryFixed: Tokens.inkOnBone
        property color m3onSecondaryFixedVariant: Tokens.inkOnBoneDim
        property color m3tertiaryFixed: Tokens.bone
        property color m3tertiaryFixedDim: Tokens.inkDim
        property color m3onTertiaryFixed: Tokens.inkOnBone
        property color m3onTertiaryFixedVariant: Tokens.inkOnBoneDim
        property color m3success: Tokens.ink
        property color m3onSuccess: Tokens.paper
        property color m3successContainer: Tokens.tint16
        property color m3onSuccessContainer: Tokens.ink
    }

    // Compositor-facing compatibility values stay inert inside the editor.
    property bool borderless: false
    property int borderWidth: 2

    colors: QtObject {
        property color colSubtext: Tokens.inkMuted
        property color colLayer0Base: Tokens.paper
        property color colLayer0: Tokens.paper
        property color colOnLayer0: Tokens.ink
        property color colLayer0Hover: Tokens.tint5
        property color colLayer0Active: Tokens.tint10
        property color colLayer0Border: Tokens.line
        property color colLayer1Base: Tokens.paper
        property color colLayer1: Tokens.paper
        property color colOnLayer1: Tokens.ink
        property color colOnLayer1Inactive: Tokens.inkMuted
        property color colLayer1Hover: Tokens.tint5
        property color colLayer1Active: Tokens.tint16
        property color colLayer2Base: Tokens.paperLift
        property color colLayer2: Tokens.paperLift
        property color colLayer2Hover: Tokens.tint5
        property color colLayer2Active: Tokens.tint16
        property color colLayer2Disabled: Tokens.tint5
        property color colOnLayer2: Tokens.ink
        property color colOnLayer2Disabled: Tokens.inkFaint
        property color colLayer3Base: Tokens.paperLift
        property color colLayer3: Tokens.paperLift
        property color colLayer3Hover: Tokens.tint5
        property color colLayer3Active: Tokens.tint16
        property color colOnLayer3: Tokens.ink
        property color colLayer4Base: Tokens.paperLift
        property color colLayer4: Tokens.paperLift
        property color colLayer4Hover: Tokens.tint5
        property color colLayer4Active: Tokens.tint16
        property color colOnLayer4: Tokens.ink
        property color colPrimary: Tokens.sun
        property color colOnPrimary: Tokens.paper
        property color colPrimaryHover: root.withAlpha(Tokens.sun, 0.9)
        property color colPrimaryActive: root.withAlpha(Tokens.sun, 0.82)
        property color colPrimaryContainer: Tokens.tint10
        property color colPrimaryContainerHover: Tokens.tint16
        property color colPrimaryContainerActive: Tokens.tint16
        property color colOnPrimaryContainer: Tokens.ink
        property color colSecondary: Tokens.bone
        property color colSecondaryHover: Tokens.bone
        property color colSecondaryActive: root.withAlpha(Tokens.bone, 0.9)
        property color colOnSecondary: Tokens.inkOnBone
        property color colSecondaryContainer: Tokens.bone
        property color colSecondaryContainerHover: Tokens.bone
        property color colSecondaryContainerActive: root.withAlpha(Tokens.bone, 0.9)
        property color colOnSecondaryContainer: Tokens.inkOnBone
        property color colTertiary: Tokens.inkDim
        property color colTertiaryHover: Tokens.ink
        property color colTertiaryActive: Tokens.ink
        property color colTertiaryContainer: Tokens.tint10
        property color colTertiaryContainerHover: Tokens.tint16
        property color colTertiaryContainerActive: Tokens.tint16
        property color colOnTertiary: Tokens.paper
        property color colOnTertiaryContainer: Tokens.ink
        property color colBackgroundSurfaceContainer: Tokens.paper
        property color colBackgroundSurfaceContainerAccent: Tokens.paper
        property color colSurfaceContainerLow: Tokens.paperLift
        property color colSurfaceContainer: Tokens.paperLift
        property color colSurfaceContainerHigh: Tokens.tint5
        property color colSurfaceContainerHighest: Tokens.tint10
        property color colSurfaceContainerHighestHover: Tokens.tint10
        property color colSurfaceContainerHighestActive: Tokens.tint16
        property color colOnSurface: Tokens.ink
        property color colOnSurfaceVariant: Tokens.inkDim
        property color colTooltip: Tokens.paperLift
        property color colOnTooltip: Tokens.ink
        property color colScrim: root.withAlpha(Tokens.paper, 0.72)
        property color colShadow: root.withAlpha(Tokens.paper, 0.42)
        property color colOutline: Tokens.line
        property color colOutlineVariant: Tokens.lineSoft
        property color colError: Tokens.alert
        property color colErrorHover: Tokens.alert
        property color colErrorActive: root.withAlpha(Tokens.alert, 0.82)
        property color colOnError: Tokens.paper
        property color colErrorContainer: Tokens.tint10
        property color colErrorContainerHover: Tokens.tint16
        property color colErrorContainerActive: Tokens.tint16
        property color colOnErrorContainer: Tokens.ink
    }

    rounding: QtObject {
        property real scale: Config.options.appearance.sharpMode ? 0 : 1
        readonly property int standard: scale === 0 ? 0 : Tokens.radius
        property int unsharpen: standard
        property int unsharpenmore: standard
        property int verysmall: standard
        property int small: standard
        property int normal: standard
        property int large: standard
        property int verylarge: standard
        property int full: scale === 0 ? 0 : 9999
        property int screenRounding: standard
        property int windowRounding: standard
    }

    font: QtObject {
        property QtObject family: QtObject {
            property string main: Tokens.ui
            property string numbers: Tokens.mono
            property string title: Tokens.display
            property string iconMaterial: "Material Symbols Rounded"
            property string iconNerd: "Symbols Nerd Font"
            property string monospace: Tokens.mono
            property string reading: Tokens.ui
            property string expressive: Tokens.ui
            property string jp: Tokens.jp
        }
        property QtObject variableAxes: QtObject {
            property var main: ({ "wght": 500 })
            property var numbers: ({ "wght": 500 })
            property var title: ({ "wght": 600 })
            property var rounded: ({ "wght": 500 })
            property var titleRounded: ({ "wght": 600 })
            // Interpolated variable axes must be stepped, not continuous: every
            // distinct value is a new font engine face, and the cache only trims
            // a few per tick. blend()/snap() keep it to steps + 1 per pair.
            readonly property int steps: 3
            function snap(t: real): real {
                return Math.round(Math.max(0, Math.min(1, t)) * steps) / steps;
            }
            function blend(from: real, to: real, t: real): real {
                return Math.round(from + (to - from) * snap(t));
            }
            function blendIn(from: real, to: real, t: real, n: int): real {
                return Math.round(from + (to - from) * Math.round(Math.max(0, Math.min(1, t)) * n) / n);
            }
        }
        property QtObject pixelSize: QtObject {
            property real smallest: Tokens.fTiny
            property real smaller: Tokens.fMicro
            property real smallie: Tokens.fSmall
            property real small: Tokens.fSmall
            property real normal: Tokens.fBody
            property real large: Tokens.fRow
            property real larger: Tokens.fValue
            property real huge: Tokens.fValue
            property real hugeass: Tokens.fTitle
            property real title: Tokens.fValue
        }
        property real trackLabel: Tokens.trackLabel
        property real trackMark: Tokens.trackMark
    }

    readonly property real animMultiplier: Tokens.reduceMotion ? 0 : Tokens.motionScale
    readonly property bool reducedMotion: Tokens.reduceMotion

    animationCurves: QtObject {
        readonly property list<real> expressiveFastSpatial: Tokens.curveFastSpatial
        readonly property list<real> expressiveDefaultSpatial: Tokens.curveDefaultSpatial
        readonly property list<real> expressiveSlowSpatial: Tokens.curveSlowSpatial
        readonly property list<real> expressiveEffects: Tokens.curveDefaultEffects
        readonly property list<real> emphasized: Tokens.curveEmphasized
        readonly property list<real> emphasizedFirstHalf: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82]
        readonly property list<real> emphasizedLastHalf: [5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property list<real> emphasizedAccel: [0.3, 0, 0.8, 0.15, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property list<real> standard: Tokens.curveStandard
        readonly property list<real> standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property list<real> standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property real expressiveFastSpatialDuration: Tokens.durFastSpatial
        readonly property real expressiveDefaultSpatialDuration: Tokens.durDefaultSpatial
        readonly property real expressiveSlowSpatialDuration: Tokens.durSlowSpatial
        readonly property real expressiveEffectsDuration: Tokens.durDefaultEffects
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: Tokens.swap
            property int type: Tokens.ease
            property list<real> bezierCurve: animationCurves.standard
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveSmall: QtObject {
            property int duration: Tokens.move
            property int type: Tokens.ease
            property list<real> bezierCurve: animationCurves.standard
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveSmall.duration
                    easing.type: root.animation.elementMoveSmall.type
                    easing.bezierCurve: root.animation.elementMoveSmall.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: Tokens.durNormal
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveExit: QtObject {
            property int duration: Tokens.durSmall
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedAccel
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveExit.duration
                    easing.type: root.animation.elementMoveExit.type
                    easing.bezierCurve: root.animation.elementMoveExit.bezierCurve
                }
            }
        }

        // Context menus and popups opening under the cursor: the WINDOW the
        // cascade lives in. The reveal scalar runs LINEAR and every slice
        // eases its own arrival — the sidebar's rhythm (StaggeredEntrance:
        // 26 ms stagger, ~400 ms fade per row). Two clocks, strictly
        // separate: the card body + plate land in the first ~22% (the menu
        // pops in and STANDS STILL), and the rows wave in inside it from
        // there to 100%. One global curve over the scalar was the blink
        // (emphasizedDecel is ~85% done at 30% of its time — every row
        // flashed at once); a body that grows across the whole window makes
        // the menu itself perform as a cascade item and hides the rows'
        // wave behind its drift. The exit stays short and flat: a menu
        // waving away, not a page leaving.
        // Duration only: the scalar runs Linear and the slices carry the
        // easing, so there is no curve to hand out. Kept short: 640 ms read
        // well once, then made a menu opened many times a day feel stuck.
        property QtObject popupEnter: QtObject {
            property int duration: Tokens.swap
        }

        property QtObject popupExit: QtObject {
            property int duration: Tokens.move
        }

        property QtObject elementMoveSlow: QtObject {
            property int duration: Tokens.durNormal
            property int type: Tokens.ease
            property list<real> bezierCurve: animationCurves.standard
            property int velocity: 850
            property Component colorAnimation: Component {
                ColorAnimation {
                    duration: root.animation.elementMoveSlow.duration
                    easing.type: root.animation.elementMoveSlow.type
                    easing.bezierCurve: root.animation.elementMoveSlow.bezierCurve
                }
            }
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveSlow.duration
                    easing.type: root.animation.elementMoveSlow.type
                    easing.bezierCurve: root.animation.elementMoveSlow.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: Tokens.move
            property int type: Tokens.ease
            property list<real> bezierCurve: animationCurves.standard
            property int velocity: 850
            property Component colorAnimation: Component {
                ColorAnimation {
                    duration: root.animation.elementMoveFast.duration
                    easing.type: root.animation.elementMoveFast.type
                    easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
                }
            }
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementMoveFast.duration
                    easing.type: root.animation.elementMoveFast.type
                    easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
                }
            }
        }

        /**
         * A selection that follows the keyboard (Alt+Tab's highlight). Shorter than
         * elementMoveFast so a held key reads as one motion, and deliberately without
         * `alwaysRunToEnd`: a Behavior retargets from wherever the value is, and running
         * each leg to its end would queue every press behind the last one.
         */
        property QtObject elementMoveSnap: QtObject {
            property int duration: Tokens.snap
            property int type: Tokens.easeSnap
            property list<real> bezierCurve: animationCurves.expressiveFastSpatial
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveSnap.duration
                    easing.type: root.animation.elementMoveSnap.type
                    easing.bezierCurve: root.animation.elementMoveSnap.bezierCurve
                }
            }
        }

        property QtObject elementResize: QtObject {
            property int duration: Tokens.swap
            property int type: Tokens.ease
            property list<real> bezierCurve: animationCurves.emphasized
            property int velocity: 650
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.elementResize.duration
                    easing.type: root.animation.elementResize.type
                    easing.bezierCurve: root.animation.elementResize.bezierCurve
                }
            }
        }

        // Every size change that happens *inside* the bar reads from here: the
        // widgets and the island backgrounds that wrap them have to reach their
        // new size at the same instant, and they only do that if they share one
        // duration and one curve. A widget that animates its own implicitWidth
        // faster than the island around it makes the island look like it is
        // chasing the content (and vice versa).
        // 280ms is the duration the Dynamic Island already used; the fast
        // spatial curve keeps its slight overshoot without the OutBack tail.
        property QtObject barResize: QtObject {
            property int duration: Math.round(280 * root.animMultiplier)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveFastSpatial
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.barResize.duration
                    easing.type: root.animation.barResize.type
                    easing.bezierCurve: root.animation.barResize.bezierCurve
                }
            }
        }

        // Dashboard indicators use a staged transition: the slot changes size
        // before/after the icon pop. Keep these slower and softer than the
        // global barResize clock without slowing every other responsive widget.
        property QtObject dashboardIndicatorResize: QtObject {
            property int duration: Math.round(420 * root.animMultiplier)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.standard
        }

        property QtObject dashboardIndicatorPop: QtObject {
            property int enterDuration: Math.round(360 * root.animMultiplier)
            property int exitDuration: Math.round(280 * root.animMultiplier)
            property int cueDelay: Math.round(90 * root.animMultiplier)
            property int exitHoldDuration: Math.round(220 * root.animMultiplier)
            property int enterType: Easing.OutBack
            property real enterOvershoot: 1.18
            property int exitType: Easing.BezierSpline
            property list<real> exitCurve: animationCurves.emphasizedAccel
        }

        // The bar and the wrapped frame leaving the screen together: a
        // fullscreen window taking over, media mode, or a placement swap. The
        // exit accelerates away and the entrance decelerates in, so a swap does
        // not read as two halves of the same easing.
        property QtObject shellEdgeSlide: QtObject {
            property int exitDuration: Math.round(260 * root.animMultiplier)
            property int enterDuration: Math.round(420 * root.animMultiplier)
            property int swapHold: Math.round(90 * root.animMultiplier)
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.shellEdgeSlide.enterDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.animationCurves.emphasized
                }
            }
        }

        // Sidebars sliding in and out, and the wallpaper parallax that follows them.
        // No overshoot anywhere: expressive spatial curves kick off at ~3x linear speed and
        // bounce the wallpaper past its rest, which reads as hard. The sidebar enters on M3
        // emphasized (gentle start, long settle) and leaves accelerating, like end4's layer
        // animations; the wallpaper runs its own, longer emphasized clock in both directions,
        // since an accelerating exit is invisible for a sidebar but stops the wallpaper dead.
        property QtObject sidebarSlide: QtObject {
            property int enterDuration: Math.round(500 * root.animMultiplier)
            property int exitDuration: Math.round(500 * root.animMultiplier)
            property list<real> enterCurve: root.animationCurves.emphasized
            property list<real> exitCurve: root.animationCurves.emphasized
            property int parallaxDuration: Math.round(700 * root.animMultiplier)
            property list<real> parallaxCurve: root.animationCurves.emphasized
        }

        property QtObject clickBounce: QtObject {
            property int duration: Math.round(400 * root.animMultiplier)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property int velocity: 850
            property Component numberAnimation: Component {
                NumberAnimation {
                    alwaysRunToEnd: true
                    duration: root.animation.clickBounce.duration
                    easing.type: root.animation.clickBounce.type
                    easing.bezierCurve: root.animation.clickBounce.bezierCurve
                }
            }
        }

        // One lens shared by every dock icon. pointerLag smooths the pointer the
        // lens follows (critically damped, never overshoots); strengthDuration
        // is how long the lens takes to grow in on enter. Past the window edge
        // there are no pointer samples, so the exit is timed: exitDuration, on
        // a curve that starts and ends gently.
        property QtObject dockMagnificationScale: QtObject {
            property QtObject fast: QtObject {
                property real pointerLag: 0
                property int strengthDuration: Math.round(90 * root.animMultiplier)
                property int exitDuration: Math.round(220 * root.animMultiplier)
            }
            property QtObject balanced: QtObject {
                property real pointerLag: 28
                property int strengthDuration: Math.round(150 * root.animMultiplier)
                property int exitDuration: Math.round(280 * root.animMultiplier)
            }
            property QtObject smooth: QtObject {
                property real pointerLag: 60
                property int strengthDuration: Math.round(220 * root.animMultiplier)
                property int exitDuration: Math.round(340 * root.animMultiplier)
            }
            property int hoverExitGrace: 90
        }

        // Retained for discrete magnification feedback in secondary popups.
        property QtObject dockMagnification: QtObject {
            property int duration: Math.round(220 * root.animMultiplier)
            property int type: Easing.OutBack
            property real overshoot: 1.35
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.dockMagnification.duration
                    easing.type: root.animation.dockMagnification.type
                    easing.overshoot: root.animation.dockMagnification.overshoot
                }
            }
        }

        property QtObject scroll: QtObject {
            property int duration: Math.round(200 * root.animMultiplier)
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: root.animationCurves.standardDecel
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.scroll.duration
                    easing.type: root.animation.scroll.type
                    easing.bezierCurve: root.animation.scroll.bezierCurve
                }
            }
        }

        property QtObject menuDecel: QtObject {
            property int duration: Math.round(350 * root.animMultiplier)
            property int type: Easing.OutExpo
        }
    }

    sizes: QtObject {
        property real minimumTouchTarget: Tokens.rowH
        readonly property real space1: Tokens.s1
        readonly property real space2: Tokens.s2
        readonly property real space3: Tokens.s3
        readonly property real space4: Tokens.s4
        readonly property real space5: Tokens.s5
        readonly property real space6: Tokens.s6
        readonly property real controlHeight: Tokens.ctlH


        // Snap step for desktop widgets and icons on the wallpaper canvas.
        //
        // Ten pixels is a fine-positioning aid for a mouse: it takes the jitter out of a
        // drag without really constraining where something lands. A finger cannot place
        // anything that precisely, and a home screen is supposed to look laid out on a
        // grid rather than merely tidy — so a touch-first family snaps to a step coarse
        // enough to read as cells, the way Android's home screen does.
        // What this family wants when nothing is configured. Kept separate from the
        // resolved value below so a settings control can offer it as the fallback without
        // reading a property that depends on the very key it writes — that was a binding
        // loop, and the page it was on rendered empty.
        readonly property real familyWidgetGridStep: PanelFamily.touchFirst ? 40 : 10

        property real widgetGridStep: {
            const configured = Config.options?.background?.widgets?.gridStep ?? 0;
            return configured > 0 ? configured : root.sizes.familyWidgetGridStep;
        }
        property real baseBarHeight: PanelFamily.touchFirst
            ? Math.max(root.sizes.minimumTouchTarget, Config.options.bar.sizes.height)
            : Config.options.bar.sizes.height
        property real barHeight: BarInteraction.cornerStyle === 1 ? (baseBarHeight + root.sizes.hyprlandGapsOut * 2) : baseBarHeight
        // Bar widgets were drawn against a 40px horizontal bar and a 44px vertical one, and
        // most of them size their outer plate off the bar while leaving the glyph inside at
        // the number it was drawn with. On a touch-first family the bar is taller than that
        // by definition, so those widgets became big plates around small icons. Scaling the
        // insides by the same ratio is a no-op at the default and correct everywhere else.
        readonly property real barReferenceHeight: 40
        readonly property real barReferenceWidth: 44
        readonly property real barContentScale: root.sizes.baseBarHeight / root.sizes.barReferenceHeight
        readonly property real verticalBarContentScale: root.sizes.verticalBarWidth / root.sizes.barReferenceWidth

        property real barCenterSideModuleWidth: Config.options?.bar.verbose ? 360 : 140
        property real barCenterSideModuleWidthShortened: 280
        property real barCenterSideModuleWidthHellaShortened: 190
        property real barShortenScreenWidthThreshold: 1200 // Shorten if screen width is at most this value
        property real barHellaShortenScreenWidthThreshold: 1000 // Shorten even more...
        property real elevationMargin: Tokens.s3
        property real toolbarHeight: Tokens.rowH
        // The drawer is the Hub's settings measure compressed into desktop
        // chrome. One owner keeps every provider page on the same width.
        property real editModeMargin: Tokens.s5
        property real editModeEdgeMargin: Tokens.s3
        property real editModeDrawerWidth: Tokens.railW + Tokens.s7 * 3
        property real fabShadowRadius: 5
        property real fabHoveredShadowRadius: 7
        property real hyprlandGapsOut: 5
        property real mediaControlsWidth: 440
        property real mediaControlsHeight: 160
        property real notificationPopupWidth: 410
        property real osdWidth: 200
        property real searchWidthCollapsed: 350
        property real searchWidth: 500
        property real sidebarWidth: 460
        property real sidebarWidthExtended: 750
        property real baseVerticalBarWidth: Config.options.bar.sizes.width
        property real verticalBarWidth: baseVerticalBarWidth
        property real verticalBarWindowWidth: BarInteraction.cornerStyle === 1 ? (baseVerticalBarWidth + root.sizes.hyprlandGapsOut * 2) : baseVerticalBarWidth
        property real wallpaperSelectorWidth: 1200
        property real wallpaperSelectorHeight: 690
        property real wallpaperSelectorSidebarWidth: 180
        property real wallpaperSelectorSidebarButtonHeight: 48
        property real wallpaperSelectorSidebarHorizontalPadding: 6
        property real wallpaperSelectorSidebarButtonSpacing: 3
        property real wallpaperSelectorSidebarGroupSpacing: 10
        property real wallpaperSelectorSearchWidth: 300
        property real wallpaperSelectorSortDialogWidth: 280
        property real wallpaperSelectorItemMargins: 8
        property real wallpaperSelectorItemPadding: 6
        property int dockButtonSize: Math.round((Config.options?.dock.height ?? 60) * 0.85)
    }

    syntaxHighlightingTheme: root.m3colors.darkmode ? "Monokai" : "ayu Light"
}
