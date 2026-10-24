pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons
import shell.services

Item {
    id: root

    required property real s
    required property string label
    required property string glyph
    property real value: 0
    property real from: 0
    property bool available: true
    property bool muted: false
    property bool muteEnabled: false
    property bool expandable: true
    property bool expanded: false
    readonly property bool motionAllowed: !Tokens.reduceMotion && !Motion.reduce
    readonly property int displayPercent: Math.round(Math.max(root.from, Math.min(1, root.value)) * 100)
    signal adjusted(real value)
    signal muteRequested()
    signal expandedRequested(bool expanded)

    implicitHeight: Tokens.rowH * s
    opacity: available ? 1 : 0.58
    Behavior on opacity {
        enabled: root.motionAllowed
        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }

    function clamp(value): real {
        return Math.max(root.from, Math.min(1, value));
    }

    function setFromInput(value): void {
        const next = root.clamp(value);
        root.adjusted(next);
    }

    function beginEditing(): void {
        if (!root.available)
            return;
        exactInput.text = String(root.displayPercent);
        exactButton.editing = true;
        exactInput.forceActiveFocus();
        exactInput.selectAll();
    }

    function finishEditing(): void {
        if (!exactButton.editing)
            return;
        const parsed = Number(exactInput.text);
        exactButton.editing = false;
        if (!isNaN(parsed))
            root.setFromInput(parsed / 100);
    }

    onDisplayPercentChanged: {
        if (root.motionAllowed)
            percentPulse.restart();
    }

    QQC.AbstractButton {
        id: iconButton
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Tokens.rowH * root.s
        height: width
        enabled: root.available && root.muteEnabled
        hoverEnabled: true
        Accessible.name: root.muted ? I18n.tr("Unmute %1").arg(root.label) : I18n.tr("Mute %1").arg(root.label)
        onClicked: {
            if (root.motionAllowed)
                iconBounce.restart();
            root.muteRequested();
        }
        background: Rectangle {
            radius: Tokens.radius * root.s
            color: root.muted ? Tokens.bone : iconButton.down ? Tokens.tint16 : iconButton.hovered ? Tokens.tint10 : Tokens.tint5
            border.width: Tokens.border
            border.color: iconButton.visualFocus ? Tokens.bone : root.muted ? Tokens.bone : Tokens.lineSoft
            Behavior on color {
                enabled: root.motionAllowed
                ColorAnimation { duration: Tokens.snap }
            }
        }
        contentItem: Text {
            text: root.glyph
            color: root.muted ? Tokens.inkOnBone : Tokens.inkDim
            font.family: "Material Symbols Rounded"
            font.pixelSize: Tokens.fValue * root.s
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Accessible.ignored: true
        }
        SequentialAnimation {
            id: iconBounce
            NumberAnimation { target: iconButton; property: "scale"; to: 0.86; duration: Tokens.snap; easing.type: Tokens.easeSnap }
            NumberAnimation { target: iconButton; property: "scale"; to: 1.08; duration: Tokens.snap; easing.type: Tokens.easeSnap }
            NumberAnimation { target: iconButton; property: "scale"; to: 1; duration: Tokens.snap; easing.type: Tokens.ease }
        }
        HoverHandler { cursorShape: root.muteEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }

    Text {
        id: labelText
        anchors.left: iconButton.right
        anchors.leftMargin: Tokens.s3 * root.s
        anchors.top: parent.top
        anchors.topMargin: Tokens.s1 * root.s
        text: root.label
        color: Tokens.ink
        font.family: Tokens.ui
        font.pixelSize: Tokens.fRow * root.s
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    QQC.AbstractButton {
        id: exactButton
        property bool editing: false
        anchors.right: chevron.left
        anchors.rightMargin: Tokens.s2 * root.s
        anchors.top: parent.top
        width: Math.max(Tokens.s7 * root.s, percentLabel.implicitWidth + Tokens.s2 * root.s)
        height: Tokens.ctlH * root.s
        hoverEnabled: true
        enabled: root.available
        Accessible.name: I18n.tr("Set %1 exactly").arg(root.label)
        onClicked: root.beginEditing()
        background: Rectangle {
            radius: Tokens.radius * root.s
            color: exactButton.editing ? Tokens.tint16 : exactButton.hovered ? Tokens.tint10 : "transparent"
            border.width: exactButton.editing || exactButton.visualFocus ? Tokens.border : 0
            border.color: exactButton.visualFocus ? Tokens.bone : Tokens.lineSoft
            Behavior on color {
                enabled: root.motionAllowed
                ColorAnimation { duration: Tokens.snap }
            }
        }
        contentItem: Item {
            Text {
                id: percentLabel
                anchors.fill: parent
                visible: !exactButton.editing
                text: !root.available ? "—" : root.muted ? I18n.tr("Muted") : root.displayPercent + "%"
                color: root.muted || !root.available ? Tokens.inkFaint : Tokens.ink
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro * root.s
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            TextInput {
                id: exactInput
                anchors.fill: parent
                visible: exactButton.editing
                color: Tokens.ink
                selectionColor: Tokens.bone
                selectedTextColor: Tokens.inkOnBone
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro * root.s
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: Math.round(root.from * 100); top: 100 }
                onAccepted: root.finishEditing()
                onActiveFocusChanged: if (!activeFocus) root.finishEditing()
            }
        }
        HoverHandler { cursorShape: Qt.IBeamCursor }
    }

    SequentialAnimation {
        id: percentPulse
        NumberAnimation { target: percentLabel; property: "scale"; to: 1.08; duration: Tokens.flap; easing.type: Tokens.easeSnap }
        NumberAnimation { target: percentLabel; property: "scale"; to: 1; duration: Tokens.flap; easing.type: Tokens.ease }
    }

    QQC.AbstractButton {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.expandable ? Tokens.ctlH * root.s : 0
        height: Tokens.ctlH * root.s
        visible: root.expandable
        hoverEnabled: true
        Accessible.name: root.expanded ? I18n.tr("Collapse %1").arg(root.label) : I18n.tr("Expand %1").arg(root.label)
        onClicked: root.expandedRequested(!root.expanded)
        background: Rectangle {
            radius: Tokens.radius * root.s
            color: chevron.down ? Tokens.tint16 : chevron.hovered ? Tokens.tint10 : "transparent"
        }
        contentItem: Text {
            text: "expand_more"
            color: Tokens.inkDim
            font.family: "Material Symbols Rounded"
            font.pixelSize: Tokens.fRow * root.s
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            rotation: root.expanded ? 180 : 0
            Behavior on rotation {
                enabled: root.motionAllowed
                NumberAnimation { duration: Tokens.move; easing.type: Tokens.ease }
            }
            Accessible.ignored: true
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }

    QQC.Slider {
        id: slider
        anchors.left: iconButton.right
        anchors.leftMargin: Tokens.s3 * root.s
        anchors.right: chevron.visible ? chevron.left : parent.right
        anchors.rightMargin: chevron.visible ? Tokens.s2 * root.s : 0
        anchors.bottom: parent.bottom
        height: Tokens.ctlH * root.s
        from: root.from
        to: 1
        stepSize: 0.01
        snapMode: QQC.Slider.SnapAlways
        value: root.clamp(root.value)
        enabled: root.available
        Accessible.name: root.label
        onMoved: root.adjusted(value)
        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: Tokens.s1 * root.s
            radius: height / 2
            color: Tokens.tint10
            Rectangle {
                width: slider.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: root.muted || !root.available ? Tokens.inkFaint : Tokens.bone
                Behavior on width {
                    enabled: root.motionAllowed && !slider.pressed
                    NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
                }
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14 * root.s
            height: width
            radius: width / 2
            color: root.available ? Tokens.bone : Tokens.inkFaint
            border.width: Tokens.border
            border.color: Tokens.paper
            scale: slider.pressed ? 1.28 : slider.hovered || slider.visualFocus ? 1.14 : 1
            Behavior on scale {
                enabled: root.motionAllowed
                NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
            }
        }
        HoverHandler { cursorShape: Qt.PointingHandCursor }
        WheelHandler {
            enabled: root.available
            onWheel: event => {
                const direction = event.angleDelta.y >= 0 ? 1 : -1;
                root.adjusted(root.clamp(root.value + direction * 0.02));
                event.accepted = true;
            }
        }
    }
}