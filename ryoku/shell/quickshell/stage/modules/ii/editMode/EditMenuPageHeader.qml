import QtQuick
import QtQuick.Layouts
import stage.modules.common
import stage.modules.common.widgets

/**
 * The header of a menu page (the desktop menu's, the icon menu's): Edit Mode's drawer header - the way
 * back in a circle, the page title beside it - and, when the page names one
 * (`actionSymbol`), an outlined circle on the right for the way further out
 * (the page's full version in Settings).
 */
RowLayout {
    id: root

    property string title: ""
    property string actionSymbol: ""
    property string actionTooltip: ""
    signal backRequested()
    signal actionRequested()

    Layout.fillWidth: true
    Layout.leftMargin: Appearance.sizes.space1
    Layout.rightMargin: Appearance.sizes.space1
    spacing: Appearance.sizes.space3

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Appearance.sizes.controlHeight
        implicitHeight: Appearance.sizes.controlHeight
        radius: Appearance.rounding.small
        color: backMouse.containsPress ? Appearance.colors.colLayer1Active
            : backMouse.containsMouse ? Appearance.colors.colLayer1Hover
            : "transparent"

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: 18
            color: Appearance.colors.colOnSurface
        }

        MouseArea {
            id: backMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.backRequested()
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.title
        font.family: Appearance.font.family.title
        font.pixelSize: Appearance.font.pixelSize.large
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnSurface
        elide: Text.ElideRight
    }

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        visible: root.actionSymbol !== ""
        implicitWidth: Appearance.sizes.controlHeight
        implicitHeight: Appearance.sizes.controlHeight
        radius: Appearance.rounding.small
        color: actionMouse.containsPress ? Appearance.colors.colLayer1Active
            : actionMouse.containsMouse ? Appearance.colors.colLayer1Hover
            : "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        Behavior on color {
            enabled: !Appearance.reducedMotion
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: root.actionSymbol
            iconSize: 20
            color: Appearance.colors.colOnSurface
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.actionRequested()
        }

        StyledToolTip {
            extraVisibleCondition: actionMouse.containsMouse && root.actionTooltip !== ""
            text: root.actionTooltip
        }
    }
}
