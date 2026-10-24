import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import stage.modules.common
import stage.modules.common.widgets

/**
 * One row of Edit Mode's panel: a filled pill carrying a circled icon, a title,
 * an optional second line, and whatever the row's answer is on the right - a
 * chevron into a sub-page, a check, a plus, a value, a switch, or a stepper.
 *
 * The shape is the shell's grouped-list shape: full rounding on the ends of a
 * run and a tight corner between neighbours, with the pressed row swelling to
 * fully round. `first`/`last` are handed in rather than derived from the
 * sibling order the way RippleButton's `useDynamicRadius` does it, because
 * these rows are usually ListView delegates: the view recycles and reorders
 * its children, so counting siblings answers with whatever the pool happens to
 * hold rather than with the row's place in the model.
 *
 * A MouseArea rather than a RippleButton because half of these rows are also
 * drag handles - a catalogue row carried onto the desktop or onto the bar -
 * and that needs `preventStealing` against the list's own flick plus a
 * press/move/release the button does not expose. `activated()` is the click,
 * emitted only for a release that was NOT a drag.
 */
MouseArea {
    id: root

    property string symbol: ""
    property string iconSource: ""
    property string title: ""
    property string subtitle: ""
    property string valueText: ""
    // "none" | "chevron" | "check" | "add" | "value" | "switch" | "stepper"
    property string trailingKind: "chevron"
    property bool switchChecked: false
    property bool stepUpEnabled: true
    property bool stepDownEnabled: true
    property bool first: true
    property bool last: true
    // The row is the thing that is on: filled in the primary role.
    // Selection is the Ryoku inverted plate.
    property bool selected: false
    property bool destructive: false
    property bool rowEnabled: true
    property real rowPadding: Appearance.sizes.space4
    // Descriptions wrap by default. Callers opt out only for rows whose
    // secondary text is deliberately a one-line status.
    property bool subtitleWrap: true
    // A drag on this row carries something; the list it sits in must let go of
    // the gesture the moment it wins.
    property bool draggable: false
    property Flickable dragOwner: null
    // Place in the fill, for the cascade a page arrives with. -1 arrives
    // settled, which is what a row outside a run wants. ListView pages get
    // this from the view's own `populate` transition instead; this is for the
    // Repeater-built pages, which have no equivalent.
    property int staggerIndex: -1

    signal activated()

    // A row only takes the keyboard when a host hands it focus (the icon
    // menu's arrow navigation); it then reads as hovered and Enter/Space
    // are the click. Nothing in Edit Mode focuses rows, so there it is inert.
    Keys.onReturnPressed: event => { event.accepted = true; if (root.rowEnabled) root.activated(); }
    Keys.onEnterPressed: event => { event.accepted = true; if (root.rowEnabled) root.activated(); }
    Keys.onSpacePressed: event => { event.accepted = true; if (root.rowEnabled) root.activated(); }
    signal dragBegan()
    signal dragMovedTo(real sceneX, real sceneY)
    signal dragFinished(real sceneX, real sceneY)
    signal dragCancelled()
    signal stepUp()
    signal stepDown()

    implicitHeight: Math.max(Appearance.sizes.minimumTouchTarget,
        rowLayout.implicitHeight + Appearance.sizes.space3 * 2)
    hoverEnabled: true
    enabled: root.rowEnabled
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton
    // Only a row that CARRIES something holds the gesture against its list.
    // A static row must let the flick through, or a settings page cannot be
    // scrolled by dragging over the rows that fill it.
    preventStealing: root.draggable
    opacity: (root.rowEnabled ? 1 : 0.45) * revealProxy.opacity
    scale: revealProxy.scale

    // The cascade drives a PROXY rather than the row itself. StaggeredEntrance
    // assigns `opacity` and `scale` on its target, and this row's opacity
    // already carries its disabled state - an assignment would replace that
    // rule rather than join it, so a row that is disabled later would stop
    // dimming. Multiplying the proxy in keeps both.
    Item {
        id: revealProxy
        visible: false
        width: 0
        height: 0

        StaggeredEntrance {
            target: revealProxy
            index: root.staggerIndex
            active: root.staggerIndex >= 0 && !Appearance.reducedMotion
        }
    }

    readonly property color colOn: root.selected
        ? Appearance.colors.colOnSecondary
        : root.destructive ? Appearance.colors.colError : Appearance.colors.colOnSurface

    // ── The gesture ──────────────────────────────────────────────────────────
    property real _pressX: 0
    property real _pressY: 0
    property bool dragActive: false

    function _scene(mouse) {
        return root.mapToItem(null, mouse.x, mouse.y);
    }

    onPressed: mouse => {
        root._pressX = mouse.x;
        root._pressY = mouse.y;
        root.dragActive = false;
    }
    onPositionChanged: mouse => {
        if (!root.pressed || !root.draggable)
            return;
        if (!root.dragActive
                && Math.abs(mouse.x - root._pressX) < 5
                && Math.abs(mouse.y - root._pressY) < 5)
            return;
        if (!root.dragActive) {
            root.dragActive = true;
            if (root.dragOwner)
                root.dragOwner.interactive = false;
            root.dragBegan();
        }
        const p = root._scene(mouse);
        root.dragMovedTo(p.x, p.y);
    }
    onReleased: mouse => {
        const wasDrag = root.dragActive;
        root.dragActive = false;
        if (root.dragOwner)
            root.dragOwner.interactive = true;
        if (!wasDrag) {
            root.activated();
            return;
        }
        const p = root._scene(mouse);
        root.dragFinished(p.x, p.y);
    }
    onCanceled: {
        if (!root.dragActive)
            return;
        root.dragActive = false;
        if (root.dragOwner)
            root.dragOwner.interactive = true;
        root.dragCancelled();
    }

    // Kept as caller-facing compatibility inputs; the paper-row treatment has
    // one corner everywhere instead of changing shape across a recycled run.
    property real hostRadius: Appearance.rounding.verylarge
    property real hostPadding: Appearance.sizes.space4
    readonly property real rEnd: Appearance.rounding.small
    readonly property real rSeam: Appearance.rounding.small
    readonly property real rPressed: Appearance.rounding.small

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: Appearance.rounding.small
        antialiasing: true
        color: root.selected
            ? Appearance.colors.colSecondary
            : root.pressed
                ? Appearance.colors.colLayer1Active
                : root.containsMouse || root.activeFocus
                    ? Appearance.colors.colLayer1Hover
                    : "transparent"
        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(pill)
        }
    }

    // Folio rows are separated by a hairline rather than by stacked filled
    // pills. The selected plate hides the rule naturally.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Appearance.sizes.space4
        anchors.right: parent.right
        anchors.rightMargin: Appearance.sizes.space4
        anchors.top: parent.top
        height: 1
        visible: !root.selected
        color: Appearance.colors.colOutlineVariant
    }

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.leftMargin: root.rowPadding
        anchors.rightMargin: root.trailingKind === "stepper" ? Appearance.sizes.space1 : root.rowPadding
        anchors.topMargin: Appearance.sizes.space3
        anchors.bottomMargin: Appearance.sizes.space3
        spacing: Appearance.sizes.space3

        // A quiet icon plate preserves catalogue recognition without competing
        // with the row's selected surface.
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            visible: root.symbol !== "" || root.iconSource !== ""
            implicitWidth: 30
            implicitHeight: 30
            radius: Appearance.rounding.small
            color: root.selected
                ? Appearance.withAlpha(Appearance.colors.colOnSecondary, 0.12)
                : root.trailingKind === "switch" && root.switchChecked
                    ? Appearance.colors.colLayer1Active
                    : "transparent"

            Behavior on color {
                enabled: !Appearance.reducedMotion
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MaterialSymbol {
                id: symbolGlyph
                anchors.centerIn: parent
                visible: root.iconSource === ""
                text: root.symbol
                iconSize: 18
                fill: (root.trailingKind === "switch" && root.switchChecked) ? 1 : 0
                color: root.colOn

                // A glyph that changes under a settled row (a copy turning
                // into a check, pin into unpin) pops back in from small, so
                // the change is seen rather than just swapped.
                onTextChanged: {
                    if (!Appearance.reducedMotion && root.visible)
                        symbolPop.restart();
                }
                SequentialAnimation {
                    id: symbolPop
                    NumberAnimation {
                        target: symbolGlyph; property: "scale"; to: 0.55
                        duration: 70; easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: symbolGlyph; property: "scale"; to: 1
                        duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2.2
                    }
                }
            }

            IconImage {
                anchors.centerIn: parent
                visible: root.iconSource !== ""
                implicitSize: 22
                source: root.iconSource
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 0
            spacing: Appearance.sizes.space1

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.title
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                color: root.colOn
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: root.subtitle !== ""
                text: root.subtitle
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Normal
                color: root.selected ? Appearance.colors.colOnSecondary : Appearance.colors.colSubtext
                opacity: 1
                elide: root.subtitleWrap ? Text.ElideNone : Text.ElideRight
                wrapMode: root.subtitleWrap ? Text.Wrap : Text.NoWrap
                maximumLineCount: root.subtitleWrap ? 2147483647 : 1
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            Layout.minimumWidth: 0
            Layout.maximumWidth: Math.min(120, root.width * 0.32)
            visible: root.valueText !== "" && root.trailingKind !== "stepper"
            text: root.valueText
            font.family: Appearance.font.family.numbers
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colOn
            opacity: 0.8
            elide: Text.ElideRight
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "chevron" || root.trailingKind === "check"
                || root.trailingKind === "add"
            text: root.trailingKind === "check" ? "check_circle"
                : root.trailingKind === "add" ? "add_circle" : "chevron_right"
            iconSize: root.trailingKind === "chevron" ? 22 : 20
            fill: root.trailingKind === "check" ? 1 : 0
            color: root.colOn
            opacity: root.trailingKind === "chevron" ? 0.7 : 1
        }

        StyledSwitch {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "switch"
            checked: root.switchChecked
            // The row owns the gesture: a 30px target inside a 58px row is a
            // target people miss, and the switch reads as a state either way.
            enabled: false
        }

        // The stepper, for the handful of rows that carry a number.
        Row {
            Layout.alignment: Qt.AlignVCenter
            visible: root.trailingKind === "stepper"
            spacing: 0

            StepButton {
                symbol: "remove"
                enabled: root.stepDownEnabled
                onTriggered: root.stepDown()
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                horizontalAlignment: Text.AlignHCenter
                text: root.valueText
                font.pixelSize: Appearance.font.pixelSize.small
                font.family: Appearance.font.family.numbers
                color: root.colOn
            }
            StepButton {
                symbol: "add"
                enabled: root.stepUpEnabled
                onTriggered: root.stepUp()
            }
        }
    }

    component StepButton: Rectangle {
        id: step
        property string symbol: ""
        signal triggered()

        width: Appearance.sizes.controlHeight
        height: Appearance.sizes.controlHeight
        radius: Appearance.rounding.small
        color: stepMouse.containsPress
            ? Appearance.colors.colLayer1Active
            : stepMouse.containsMouse
                ? Appearance.colors.colLayer1Hover
                : "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(step)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: step.symbol
            iconSize: 19
            color: step.enabled ? root.colOn : Appearance.m3colors.m3outline
        }

        MouseArea {
            id: stepMouse
            anchors.fill: parent
            enabled: step.enabled
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: step.triggered()
        }
    }
}
