pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ryoku.Ui.Singletons
import stage.modules.common
import stage.modules.common.widgets
import stage.modules.ii.editMode

/**
 * A menu about one item (a desktop icon, today): a plate naming the item on
 * top, and under it the card of actions, with pages of its own.
 *
 * Desktop item menus use the same paper card, row treatment and transition
 * language as the desktop menu. The item plate remains specific to this
 * surface so its icon, name and path stay visible while navigating pages.
 *
 * closeRequested fires only after the exit motion; the host may then unload.
 */
FocusScope {
    id: root
    property string title: ""
    property string subtitle: ""
    property url iconSource: ""
    property point anchorPoint: Qt.point(0, 0)
    property var actions: []
    property Component pageComponent: null
    // How deep `pageComponent` sits: 0 is the actions, a page off them is 1,
    // a page off that is 2. It decides which way a page change slides.
    property int pageDepth: root.pageComponent ? 1 : 0
    property bool closing: false
    signal actionTriggered(string actionId)
    signal closeRequested()
    signal backRequested()
    // The host's selection, when the menu speaks of a set: Ctrl+A on the
    // action page asks the host to select everything it owns.
    signal selectAllRequested()
    // The action Repeater, published by the action page on create/destroy.
    property var actionRows: null

    // A row that just did its job (a copy) answers in place: it fills with
    // primary, its icon turns into a check and its label into `doneText`.
    // Kept beside `actions`, not in it - a new actions array would rebuild
    // every row and the fill would snap instead of easing in.
    property string doneId: ""
    property string doneText: ""
    function confirmAction(id: string, text: string): void {
        root.doneText = text;
        root.doneId = id;
    }

    readonly property int padding: Tokens.s2
    readonly property real cardRadius: Tokens.radius

    function dismiss() {
        if (root.closing)
            return;
        root.closing = true;
        enterMotion.stop();
        exitMotion.restart();
    }

    // ── Enter and exit ───────────────────────────────────────────────────────
    // The desktop menu's motion (DesktopMenuCard): plate and card grow out
    // of the corner under the pointer as one (0.85 -> 1 on elementMoveEnter)
    // while fading in on elementMoveFast, and leave as one on
    // elementMoveExit. No row cascade.
    property real grow: 0
    property real reveal: 0
    readonly property bool _motion: !Tokens.reduceMotion

    ParallelAnimation {
        id: enterMotion
        NumberAnimation {
            target: root; property: "grow"; to: 1
            duration: root._motion ? Tokens.move : 0
            easing.type: Tokens.ease
        }
        NumberAnimation {
            target: root; property: "reveal"; to: 1
            duration: root._motion ? Tokens.snap : 0
            easing.type: Tokens.ease
        }
    }
    ParallelAnimation {
        id: exitMotion
        NumberAnimation {
            target: root; property: "grow"; to: 0.5
            duration: root._motion ? Tokens.move : 0
            easing.type: Tokens.ease
        }
        NumberAnimation {
            target: root; property: "reveal"; to: 0
            duration: root._motion ? Tokens.snap : 0
            easing.type: Tokens.ease
        }
        onFinished: root.closeRequested()
    }

    // ── Pages ────────────────────────────────────────────────────────────────
    // The page on show lags the requested one by the out half of the slide:
    // the old page leaves toward where it came from, then the new one comes
    // in from the other side. Deeper slides left, shallower slides right.
    property Component displayedPage: null
    property int displayedDepth: 0
    property int _slideDir: 1
    readonly property real pageSlide: Tokens.s6 + Tokens.s1
    property real pageOffset: 0
    property real pageOpacity: 1

    onPageComponentChanged: {
        if (root.closing)
            return;
        root._slideDir = root.pageDepth >= root.displayedDepth ? 1 : -1;
        if (!root._motion || root.reveal < 1) {
            root.displayedPage = root.pageComponent;
            root.displayedDepth = root.pageDepth;
            return;
        }
        pageMotion.restart();
    }
    SequentialAnimation {
        id: pageMotion
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOffset"; to: -root._slideDir * root.pageSlide
                duration: Tokens.move
                easing.type: Tokens.ease
            }
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 0
                duration: Tokens.snap
                easing.type: Tokens.ease
            }
        }
        ScriptAction {
            script: {
                root.displayedPage = root.pageComponent;
                root.displayedDepth = root.pageDepth;
                root.pageOffset = root._slideDir * root.pageSlide;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root; property: "pageOffset"; to: 0
                duration: Tokens.move
                easing.type: Tokens.ease
            }
            NumberAnimation {
                target: root; property: "pageOpacity"; to: 1
                duration: Tokens.snap
                easing.type: Tokens.ease
            }
        }
    }

    // ── Keyboard ─────────────────────────────────────────────────────────────
    // Arrow navigation over the action rows. The scope holds focus, so every
    // key lands here first. From "no row yet", Down enters at the top and Up
    // at the bottom. Only the action page: a page's own fields keep their
    // keys (rename's caret, search's list). A focused row handles Enter and
    // Space itself.
    function navRows(delta: int): bool {
        const rep = root.actionRows;
        if (!rep || root.pageComponent || root.closing || rep.count === 0)
            return false;
        let idx = -1;
        for (let i = 0; i < rep.count; ++i) {
            if (rep.itemAt(i)?.activeFocus) {
                idx = i;
                break;
            }
        }
        // |delta| >= 9999 is Home/End: an absolute jump, never a walk.
        if (Math.abs(delta) >= 9999)
            idx = delta > 0 ? rep.count - 1 : 0;
        else if (idx === -1)
            idx = delta > 0 ? 0 : rep.count - 1;
        else
            idx = Math.max(0, Math.min(rep.count - 1, idx + delta));
        rep.itemAt(idx)?.forceActiveFocus();
        return true;
    }
    focus: true
    Component.onCompleted: {
        // Opened straight onto a page (F2 → rename), that page's field
        // claims focus itself — grabbing it here, after the children have
        // completed, would steal it back.
        if (!root.pageComponent)
            root.forceActiveFocus();
        root.displayedPage = root.pageComponent;
        root.displayedDepth = root.pageDepth;
        enterMotion.start();
    }
    Keys.onEscapePressed: event => {
        event.accepted = true;
        if (root.pageComponent && !root.closing)
            root.backRequested();
        else
            root.dismiss();
    }
    Keys.onUpPressed: event => {
        if (root.navRows(-1))
            event.accepted = true;
    }
    Keys.onDownPressed: event => {
        if (root.navRows(1))
            event.accepted = true;
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)
            && !root.pageComponent) {
            // Only the action page: on the rename page the field owns Ctrl+A.
            event.accepted = true;
            root.selectAllRequested();
        } else if (event.key === Qt.Key_Home) {
            if (root.navRows(-9999))
                event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            if (root.navRows(9999))
                event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }

    // Edit Mode shrinks the whole desktop; a menu that shrinks with it is
    // both hard to read and rasterized off its native grid. The host hands in
    // the factor to undo and the cards are laid out in SCREEN pixels:
    // anchorPoint arrives in surface coordinates and is converted here, the
    // clamp runs on the unscaled extent. 1 outside the mode.
    property real counterScale: 1
    ColumnLayout {
        id: cards
        x: Math.max(Tokens.s2, Math.min(root.anchorPoint.x / root.counterScale,
            root.width / root.counterScale - width - Tokens.s2)) * root.counterScale
        y: Math.max(Tokens.s2, Math.min(root.anchorPoint.y / root.counterScale,
            root.height / root.counterScale - height - Tokens.s2)) * root.counterScale
        width: Math.max(0, Math.min(Tokens.railW + Tokens.s6, root.width - Tokens.s4))
        spacing: Tokens.s2
        opacity: root.reveal
        scale: root.counterScale * (0.85 + 0.15 * root.grow)
        transformOrigin: Item.TopLeft
        enabled: !root.closing
        Behavior on y {
            enabled: root.counterScale === 1
            NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease }
        }

        Rectangle {
            id: plate
            Layout.fillWidth: true
            implicitHeight: Tokens.rowH + Tokens.s6
            radius: root.cardRadius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.line
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.s3
                spacing: Tokens.s3
                Rectangle {
                    implicitWidth: Tokens.s7 + Tokens.s4
                    implicitHeight: Tokens.s7 + Tokens.s4
                    radius: Tokens.radius
                    color: Tokens.tint5
                    border.width: Tokens.border
                    border.color: Tokens.lineSoft
                    Image {
                        anchors.centerIn: parent
                        width: Tokens.s7
                        height: Tokens.s7
                        sourceSize: Qt.size(width, height)
                        source: root.iconSource
                        fillMode: Image.PreserveAspectFit
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.s1
                    Text {
                        Layout.fillWidth: true
                        text: root.title
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fRow
                        font.weight: Font.Medium
                        color: Tokens.ink
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.subtitle
                        visible: text.length > 0
                        color: Tokens.inkMuted
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fTiny
                        elide: Text.ElideMiddle
                    }
                }
            }
        }

        Rectangle {
            id: card
            Layout.fillWidth: true
            implicitHeight: Math.min(Math.max(Tokens.rowH + Tokens.s4, root.height - Tokens.s7 * 2),
                pageLoader.implicitHeight + root.padding * 2)
            radius: root.cardRadius
            color: Tokens.paper
            border.width: Tokens.border
            border.color: Tokens.line
            clip: true
            Behavior on implicitHeight {
                enabled: !Tokens.reduceMotion && root.reveal >= 1
                NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease }
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

            ScrollView {
                id: pageScroll
                anchors.fill: parent
                anchors.margins: root.padding
                contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                Loader {
                    id: pageLoader
                    width: pageScroll.availableWidth
                    opacity: root.pageOpacity
                    transform: Translate { x: root.pageOffset }
                    sourceComponent: root.displayedPage ?? actionPage
                    enabled: !pageMotion.running && !root.closing

                    TouchpadScrollHandler {
                        flickable: pageScroll.contentItem
                    }
                }
            }
        }
    }

    Component {
        id: actionPage
        ColumnLayout {
            spacing: Tokens.s1
            Repeater {
                id: actionRepeater
                model: root.actions
                Component.onCompleted: root.actionRows = actionRepeater
                Component.onDestruction: root.actionRows = null
                delegate: Rectangle {
                    id: actionRow
                    required property var modelData
                    required property int index
                    readonly property bool done: modelData.id === root.doneId
                    readonly property bool available: modelData.enabled !== false
                    readonly property bool destructive: modelData.destructive === true
                    Layout.fillWidth: true
                    implicitHeight: Tokens.rowH
                    radius: Tokens.radius
                    color: done ? Tokens.bone
                        : actionTap.pressed ? Tokens.tint16
                        : actionHover.hovered || activeFocus ? Tokens.tint10 : "transparent"
                    border.width: activeFocus ? Tokens.border : 0
                    border.color: Tokens.bone
                    opacity: available ? 1 : 0.4
                    activeFocusOnTab: available
                    Behavior on color { ColorAnimation { duration: Tokens.snap } }

                    MaterialSymbol {
                        id: actionIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.s3
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.done ? "check" : (actionRow.modelData.icon ?? "")
                        iconSize: Tokens.s5
                        color: actionRow.done ? Tokens.inkOnBone
                            : actionRow.destructive ? Tokens.alert : Tokens.inkDim
                    }
                    Text {
                        anchors.left: actionIcon.right
                        anchors.leftMargin: Tokens.s3
                        anchors.right: actionTail.left
                        anchors.rightMargin: Tokens.s2
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.done ? root.doneText : (actionRow.modelData.text ?? "")
                        color: actionRow.done ? Tokens.inkOnBone
                            : actionRow.destructive ? Tokens.alert : Tokens.ink
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fBody
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        id: actionTail
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.s3
                        anchors.verticalCenter: parent.verticalCenter
                        text: actionRow.modelData.submenu === true ? "›"
                            : actionRow.modelData.toggle === true
                                ? (actionRow.modelData.checked === true ? "●" : "○") : ""
                        color: actionRow.done ? Tokens.inkOnBoneDim
                            : actionRow.destructive ? Tokens.alert : Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fBody
                    }
                    HoverHandler {
                        id: actionHover
                        enabled: actionRow.available
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        id: actionTap
                        enabled: actionRow.available
                        onTapped: root.actionTriggered(actionRow.modelData.id)
                    }
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                            || event.key === Qt.Key_Space) && !event.isAutoRepeat) {
                            root.actionTriggered(actionRow.modelData.id);
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
