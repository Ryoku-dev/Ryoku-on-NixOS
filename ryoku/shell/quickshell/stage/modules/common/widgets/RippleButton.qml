import stage.modules.common
import stage.modules.common.widgets
import stage.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls

/**
 * A button with ripple effect similar to in Material Design.
 */
Button {
    id: root
    // The inner MouseArea owns pointer input and follows this flag. Controls
    // default it to false, which otherwise suppresses both the hand cursor
    // and the hover state used by tooltips for every ordinary button.
    hoverEnabled: true
    property bool toggled
    // Selected controls always use Stage's inverted surface pair; callers can
    // opt out only for semantic states such as destructive actions.
    property bool invertedSelection: true
    property string buttonText
    property bool pointingHandCursor: true
    property real buttonRadius: Appearance.rounding.small
    property real buttonRadiusPressed: buttonRadius
    property real buttonEffectiveRadius: root.down ? root.buttonRadiusPressed : root.buttonRadius
    readonly property bool isPressed: root.down
    property int rippleDuration: 1200
    property bool rippleEnabled: true
    // Some dense, static widgets do not need any motion. Keep the animated
    // Material behavior as the default, while allowing those widgets to opt
    // out without duplicating the button implementation.
    property bool animationsEnabled: true
    property bool radiusBehaviorEnabled: true
    property bool opacityBehaviorEnabled: true
    property bool scaleBehaviorEnabled: true
    property real visualScale: 1.0
    property var downAction
    property var releaseAction
    property var altAction
    property var middleClickAction
    property var backClickAction
    property var enteredAction
    property var exitedAction
    property var pressedAction
    property var positionChangedAction
    property var canceledAction

    property bool useDynamicRadius: false

    // Filled in once per container by GroupLayout.js; see GroupPosition.qml.
    // Only rows with a dynamic radius get one: most buttons never need it.
    property GroupPosition groupPosition: null
    readonly property bool groupSettled: groupPosition?.settled ?? false
    readonly property int itemIndex: useDynamicRadius ? (groupPosition?.index ?? 0) : 0
    readonly property int totalItems: useDynamicRadius ? (groupPosition?.count ?? 1) : 1

    property bool isFirst: useDynamicRadius ? (groupPosition?.isFirst ?? true) : false
    property bool isLast: useDynamicRadius ? (groupPosition?.isLast ?? true) : false

    readonly property bool prevIsPressed: useDynamicRadius && (groupPosition?.previousPressed ?? false)
    readonly property bool nextIsPressed: useDynamicRadius && (groupPosition?.nextPressed ?? false)

    function ensureGroupPosition() {
        if (root.useDynamicRadius && !root.groupPosition)
            root.groupPosition = groupPositionComponent.createObject(root, { item: root });
    }

    onUseDynamicRadiusChanged: root.ensureGroupPosition()
    Component.onCompleted: root.ensureGroupPosition()

    Component {
        id: groupPositionComponent
        GroupPosition {
            enabled: root.useDynamicRadius
        }
    }

    /// Which way a connected group runs, when the parent's type cannot say: a
    /// GridLayout that flips between a row and a column. Left undefined, the
    /// parent decides, as before.
    property var groupHorizontal: undefined

    readonly property bool isHorizontalLayout: {
        if (root.groupHorizontal !== undefined)
            return root.groupHorizontal === true;
        var p = parent;
        if (!p)
            return false;
        var pStr = p.toString();
        return (pStr.indexOf("RowLayout") !== -1 || pStr.indexOf("Row") !== -1) && pStr.indexOf("Column") === -1;
    }

    readonly property real rFull: root.buttonEffectiveRadius

    property real topLeftRadius: root.buttonEffectiveRadius
    property real topRightRadius: root.buttonEffectiveRadius
    property real bottomLeftRadius: root.buttonEffectiveRadius
    property real bottomRightRadius: root.buttonEffectiveRadius
    readonly property bool intentionalCircle: Math.abs(root.width - root.height) < 0.5
        && root.buttonEffectiveRadius >= root.height / 2 - 0.5
    readonly property real paintedTopLeftRadius: root.topLeftRadius
    readonly property real paintedTopRightRadius: root.topRightRadius
    readonly property real paintedBottomLeftRadius: root.bottomLeftRadius
    readonly property real paintedBottomRightRadius: root.bottomRightRadius


    Behavior on topLeftRadius {
        enabled: root.animationsEnabled && root.useDynamicRadius && root.groupSettled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on topRightRadius {
        enabled: root.animationsEnabled && root.useDynamicRadius && root.groupSettled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomLeftRadius {
        enabled: root.animationsEnabled && root.useDynamicRadius && root.groupSettled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }
    Behavior on bottomRightRadius {
        enabled: root.animationsEnabled && root.useDynamicRadius && root.groupSettled
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Appearance.animation.elementMoveFast.type
            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
        }
    }

    property color colBackground: "transparent"
    property color colBackgroundHover: Appearance.colors.colLayer1Hover
    property color colBackgroundActive: Appearance.colors.colLayer1Active
    property color colBackgroundToggled: Appearance.colors.colSecondary
    property color colBackgroundToggledHover: Appearance.colors.colSecondaryHover
    property color colBackgroundToggledActive: Appearance.colors.colSecondaryActive
    property color colRipple: Appearance.colors.colLayer1Active
    property color colRippleToggled: Appearance.colors.colOnSecondaryContainer
    function sameColor(left, right) {
        return String(left).toLowerCase() === String(right).toLowerCase();
    }
    readonly property bool usesInvertedPlate: root.invertedSelection
        && (root.toggled
            || root.sameColor(root.colBackground, Appearance.colors.colPrimary)
            || root.sameColor(root.colBackground, Appearance.colors.colPrimaryContainer))
    property real borderWidth: 1
    property color borderColor: root.usesInvertedPlate
        ? Appearance.colors.colSecondary : Appearance.colors.colOutlineVariant

    Behavior on buttonEffectiveRadius {
        enabled: root.animationsEnabled && root.radiusBehaviorEnabled
        animation: Appearance?.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    opacity: root.enabled ? 1 : 0.4
    property color buttonColor: root.usesInvertedPlate
        ? (root.down ? Appearance.colors.colSecondaryActive
            : root.hovered ? Appearance.colors.colSecondaryHover
            : Appearance.colors.colSecondary)
        : ColorUtils.transparentize(root.toggled
            ? (root.down ? colBackgroundToggledActive
                : root.hovered ? colBackgroundToggledHover : colBackgroundToggled)
            : (root.down ? colBackgroundActive
                : root.hovered ? colBackgroundHover : colBackground),
            root.enabled ? 0 : 0)
    property color rippleColor: root.usesInvertedPlate
        ? Appearance.colors.colSecondaryActive
        : root.toggled ? colRippleToggled : colRipple

    Behavior on opacity {
        enabled: root.animationsEnabled && root.opacityBehaviorEnabled
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    property real interactionScale: root.animationsEnabled && root.down ? 0.97 : 1
    scale: root.interactionScale * root.visualScale
    Behavior on interactionScale {
        enabled: root.animationsEnabled && root.scaleBehaviorEnabled
        NumberAnimation {
            duration: Appearance.animation.elementMoveSnap.duration
            easing.type: Appearance.animation.elementMoveSnap.type
        }
    }

    property bool rippleEverStarted: false

    function startRipple(x, y) {
        if (!root.animationsEnabled)
            return;
        root.rippleEverStarted = true;
        const stateY = buttonBackground.y;
        rippleAnim.x = x;
        rippleAnim.y = y - stateY;
        const dist = (ox, oy) => ox * ox + oy * oy;
        const stateEndY = stateY + buttonBackground.height;
        rippleAnim.radius = Math.sqrt(Math.max(dist(0, stateY), dist(0, stateEndY), dist(width, stateY), dist(width, stateEndY)));
        rippleFadeAnim.complete();
        rippleAnim.restart();
    }

    component RippleAnim: NumberAnimation {
        duration: rippleDuration
        easing.type: Appearance?.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance?.animationCurves.standardDecel
    }

    // The cursor belongs to the topmost item under the pointer, and a caller's
    // label or icon lands in `data` after this component's own children — so it
    // outranks the MouseArea below and the button kept the arrow. This claims
    // the hand by z instead. `Qt.NoButton` keeps it out of the way of every
    // real click, and it stays out of hover so the button's own hover, ripple
    // and tooltip are untouched.
    MouseArea {
        z: 9999
        anchors.fill: parent
        enabled: root.pointingHandCursor && root.enabled
        acceptedButtons: Qt.NoButton
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: root.hoverEnabled
        cursorShape: root.pointingHandCursor ? Qt.PointingHandCursor : Qt.ArrowCursor
        // Only controls with an explicit side-button action should consume
        // it. Other buttons leave the gesture available to SettingsWindow's
        // local history handler without depending on a global singleton.
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | (root.backClickAction ? Qt.BackButton | Qt.ExtraButton1 : Qt.NoButton)
        onEntered: {
            if (root.enteredAction)
                root.enteredAction();
        }
        onExited: {
            if (root.exitedAction)
                root.exitedAction();
        }
        onPressed: event => {
            if (event.button === Qt.RightButton) {
                if (root.altAction)
                    root.altAction(event);
                return;
            }
            if (event.button === Qt.MiddleButton) {
                if (root.middleClickAction)
                    root.middleClickAction();
                return;
            }
            if (event.button === Qt.BackButton || event.button === Qt.ExtraButton1) {
                if (root.backClickAction)
                    root.backClickAction(event);
                return;
            }
            root.down = true;
            longPressTimer.fired = false;
            if (root.altAction && PanelFamily.touchFirst)
                longPressTimer.restart();
            if (root.pressedAction)
                root.pressedAction(event);
            if (root.downAction)
                root.downAction();
            if (!root.rippleEnabled || !root.animationsEnabled)
                return;
            const {
                x,
                y
            } = event;
            startRipple(x, y);
        }
        onReleased: event => {
            root.down = false;
            longPressTimer.stop();
            if (event.button != Qt.LeftButton)
                return;
            // The long press already did the alt action; the release that ends it must not
            // also fire the primary one, or opening a quick toggle's settings would toggle
            // it on the way in.
            if (longPressTimer.fired) {
                // Run the alt action on release, not when the timer fires. Opening a dialog
                // while the finger is still down put its scrim under that finger, and the
                // release then dismissed what had just opened.
                if (root.altAction)
                    root.altAction();
                if (root.rippleEnabled && root.animationsEnabled)
                    rippleFadeAnim.restart();
                return;
            }
            if (root.releaseAction)
                root.releaseAction();
            root.click();
            if (!root.rippleEnabled || !root.animationsEnabled)
                return;
            rippleFadeAnim.restart();
        }
        // A finger has no right button. Everywhere the desktop shell says "right-click to
        // configure" — a quick toggle's settings dialog, most of all — a touch-first family
        // has no way in at all, so the same action is reachable by holding, which is what
        // Android uses for exactly this. Armed only when there IS an alt action, so nothing
        // else grows a hidden gesture.
        Timer {
            id: longPressTimer
            property bool fired: false
            interval: 500
            onTriggered: {
                // Only arms the release. The press visual drops so the hold reads as
                // "something happened" even though the action waits for the finger to lift.
                longPressTimer.fired = true;
                root.down = false;
            }
        }

        // The MouseArea replaces Button's built-in pointer handling, so its
        // double-click must be forwarded explicitly just like clicked above.
        onDoubleClicked: event => {
            if (event.button === Qt.LeftButton)
                root.doubleClicked();
        }
        onPositionChanged: event => {
            if (root.positionChangedAction)
                root.positionChangedAction(event);
        }
        onCanceled: event => {
            root.down = false;
            longPressTimer.stop();
            if (root.canceledAction)
                root.canceledAction(event);
            if (!root.rippleEnabled)
                return;
            rippleFadeAnim.restart();
        }
    }

    RippleAnim {
        id: rippleFadeAnim
        duration: rippleDuration * 2
        target: ripple
        property: "opacity"
        to: 0
    }

    SequentialAnimation {
        id: rippleAnim
        property real x
        property real y
        property real radius
        PropertyAction {
            target: ripple
            property: "x"
            value: rippleAnim.x
        }
        PropertyAction {
            target: ripple
            property: "y"
            value: rippleAnim.y
        }
        PropertyAction {
            target: ripple
            property: "opacity"
            value: 1
        }
        ParallelAnimation {
            RippleAnim {
                target: ripple
                properties: "implicitWidth,implicitHeight"
                from: 0
                to: rippleAnim.radius * 2
            }
        }
    }

    background: Rectangle {
        id: buttonBackground
        topLeftRadius: root.paintedTopLeftRadius
        topRightRadius: root.paintedTopRightRadius
        bottomLeftRadius: root.paintedBottomLeftRadius
        bottomRightRadius: root.paintedBottomRightRadius
        implicitHeight: 30
        color: root.buttonColor
        // The layer below no longer runs permanently, so the corners are drawn
        // by the rectangle itself most of the time.
        antialiasing: true
        border.width: root.borderWidth
        border.color: root.borderColor
        Behavior on color {
            enabled: root.animationsEnabled
            animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        // The mask exists only to clip the ripple to the rounded corners, so
        // the layer is worth its cost only while a ripple is actually painted.
        layer.enabled: root.animationsEnabled && root.rippleEnabled && ripple.rippling
        layer.samples: 8
        layer.smooth: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: buttonBackground.width
                height: buttonBackground.height
                topLeftRadius: root.paintedTopLeftRadius
                topRightRadius: root.paintedTopRightRadius
                bottomLeftRadius: root.paintedBottomLeftRadius
                bottomRightRadius: root.paintedBottomRightRadius
                antialiasing: true
            }
        }
        Item {
            id: ripple
            width: ripple.implicitWidth
            height: ripple.implicitHeight
            opacity: 0
            visible: root.animationsEnabled && ripple.rippling
            readonly property bool rippling: opacity > 0 && width > 0 && height > 0
            property real implicitWidth: 0
            property real implicitHeight: 0
            Behavior on opacity {
                enabled: root.animationsEnabled
                animation: Appearance?.animation.elementMoveFast.colorAnimation.createObject(this)
            }
            // Built on the first press instead of with the button: a settings
            // page holds hundreds of these and most are never clicked.
            Loader {
                anchors.fill: parent
                active: root.rippleEverStarted
                sourceComponent: RadialGradient {
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: root.rippleColor
                        }
                        GradientStop {
                            position: 0.3
                            color: root.rippleColor
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.rgba(root.rippleColor.r, root.rippleColor.g, root.rippleColor.b, 0)
                        }
                    }
                }
            }
            transform: Translate {
                x: -ripple.width / 2
                y: -ripple.height / 2
            }
        }
    }

    contentItem: StyledText {
        text: root.buttonText
        color: root.usesInvertedPlate
            ? Appearance.colors.colOnSecondary : Appearance.colors.colOnSurface
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
