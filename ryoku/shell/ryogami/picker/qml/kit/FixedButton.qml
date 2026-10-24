import QtQuick
import Ryoku.Ui.Singletons

// A pressable control in the masthead language: emphasis is inversion, so a held or
// confirmed control flips to a bone plate with dark ink rather than taking an accent fill.
// Idle is bare paper with a hairline; hover lifts a faint wash; press gives one small spring.
Item {
    id: btn

    property string label: ""
    property string glyph: ""
    // "toggle" holds the plate while active; "action" flashes it on press.
    property string mode: "toggle"
    property bool active: false
    property bool destructive: false
    property bool focused: false
    // Arm-then-confirm: first press arms, second within the window triggers.
    property bool confirm: false
    readonly property bool armed: btn.armState

    // A positive fixedWidth wins; otherwise the box hugs its content within [minWidth, maxWidth].
    property real fixedWidth: 0
    property real minWidth: 0
    property real maxWidth: 100000
    property real hpad: 14

    signal clicked()
    signal triggered()

    implicitHeight: 30 * Theme.scale
    implicitWidth: btn.fixedWidth > 0
        ? btn.fixedWidth
        : Math.max(btn.minWidth * Theme.scale,
                   Math.min(btn.maxWidth * Theme.scale, content.implicitWidth + btn.hpad * 2 * Theme.scale))

    readonly property color plate: btn.destructive ? Theme.tertiary : Theme.surfaceText
    readonly property color plateInk: btn.destructive ? Theme.background : Theme.surface
    readonly property bool hovered: hoverArea.containsMouse
    readonly property bool hot: btn.active || btn.holdFill || btn.armState

    property bool holdFill: false
    property bool armState: false

    Timer { id: flashTimer; interval: Theme.fast; onTriggered: btn.holdFill = false }
    Timer { id: disarmTimer; interval: 3000; onTriggered: btn.armState = false }
    function flash() { btn.holdFill = true; flashTimer.restart() }

    function _activate() {
        if (!btn.enabled)
            return
        if (btn.confirm) {
            if (btn.armState) {
                btn.armState = false
                disarmTimer.stop()
                btn.triggered()
                btn.clicked()
            } else {
                btn.armState = true
                disarmTimer.restart()
            }
            return
        }
        if (btn.mode === "action" && !btn.active)
            btn.flash()
        btn.triggered()
        btn.clicked()
    }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: Theme.radius
        scale: hoverArea.pressed && btn.enabled ? 0.94 : 1
        color: !btn.enabled ? Theme.withAlpha(Theme.surfaceText, 0.05)
             : btn.hot ? btn.plate
             : btn.hovered ? Theme.withAlpha(Theme.surfaceText, 0.09)
             : Theme.withAlpha(Theme.surfaceText, 0)
        border.width: btn.focused ? 2 : 1
        border.color: !btn.enabled ? Theme.withAlpha(Theme.outline, 0.18)
             : btn.focused ? Theme.withAlpha(Theme.surfaceText, 0.7)
             : btn.hot ? "transparent"
             : btn.hovered ? Theme.withAlpha(Theme.surfaceText, 0.24)
             : btn.destructive ? Theme.withAlpha(Theme.tertiary, 0.5)
             : Theme.withAlpha(Theme.outline, 0.4)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on scale { NumberAnimation { duration: Theme.fast; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6 * Theme.scale
        scale: box.scale

        readonly property color textColor: !btn.enabled
            ? Theme.withAlpha(Theme.surfaceText, 0.3)
            : btn.hot ? btn.plateInk
            : btn.destructive ? Theme.tertiary
            : btn.hovered ? Theme.surfaceText
            : Theme.withAlpha(Theme.surfaceText, 0.82)

        Text {
            visible: btn.glyph.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: btn.glyph
            font.family: Theme.icon
            font.pixelSize: Theme.fontLabel
            color: content.textColor
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
        Text {
            visible: btn.label.length > 0 || btn.armState
            anchors.verticalCenter: parent.verticalCenter
            text: btn.armState ? (I18n.tr("Confirm") + " " + btn.label) : btn.label
            font.family: Theme.sans
            font.weight: btn.hot ? Font.DemiBold : Font.Medium
            font.pixelSize: Theme.fontLabel
            color: content.textColor
            renderType: Text.NativeRendering
            Behavior on color { ColorAnimation { duration: Theme.fast } }
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: btn._activate()
    }
}
