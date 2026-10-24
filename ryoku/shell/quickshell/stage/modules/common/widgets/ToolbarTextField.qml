import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import stage.modules.common
import stage.modules.common.widgets

TextField {
    id: filterField

    property alias colBackground: background.color

    Layout.fillHeight: false
    implicitWidth: 200
    implicitHeight: 36
    padding: Appearance.sizes.space2

    // The built-in placeholder cannot elide, so a bounded copy is painted
    // below while the public placeholderText API remains unchanged.
    placeholderTextColor: "transparent"
    color: Appearance.colors.colOnSurface
    font {
        family: Appearance.font.family.main
        pixelSize: Appearance.font.pixelSize.smallie
        weight: Font.Normal
        hintingPreference: Font.PreferFullHinting
        variableAxes: Appearance.font.variableAxes.main
    }
    renderType: Text.NativeRendering
    selectedTextColor: Appearance.colors.colOnSecondary
    selectionColor: Appearance.colors.colSecondary

    // Set this to the item that should receive focus (and key events)
    // when Ctrl is held, e.g. cheatsheetBackground for tab switching.
    property Item keyNavTarget: null

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Control || (event.modifiers & Qt.ControlModifier)) && keyNavTarget) {
            keyNavTarget.forceActiveFocus();
            event.accepted = false;
        }
    }

    background: Rectangle {
        id: background
        color: "transparent"
        radius: Appearance.rounding.small
        border.width: filterField.activeFocus ? 2 : 1
        border.color: filterField.activeFocus
            ? Appearance.colors.colOnSurface
            : fieldMouse.containsMouse
                ? Appearance.colors.colOutline
                : Appearance.colors.colOutlineVariant
        Behavior on border.color {
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
        }
    }

    StyledText {
        z: 2
        anchors.left: parent.left
        anchors.leftMargin: filterField.leftPadding
        anchors.right: parent.right
        anchors.rightMargin: filterField.rightPadding
        anchors.verticalCenter: parent.verticalCenter
        visible: filterField.text.length === 0
        text: filterField.placeholderText
        color: Appearance.colors.colSubtext
        font: filterField.font
        elide: Text.ElideRight
    }

    StyledTextContextMenuLoader {
        id: contextMenu
        targetField: filterField
    }

    MouseArea {
        id: fieldMouse
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.IBeamCursor
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                filterField.forceActiveFocus();
                contextMenu.popup(mouse.x, mouse.y);
            }
        }
    }
}
