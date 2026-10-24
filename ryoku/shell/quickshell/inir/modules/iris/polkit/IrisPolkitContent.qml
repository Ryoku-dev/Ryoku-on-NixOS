pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import inir.services
import inir.modules.common
import inir.modules.common.functions
import inir.modules.common.widgets
import inir.modules.iris.style
import inir.modules.iris.components
import shell.services as Ryoku

// PAM state lives entirely in the Ryoku daemon's `Polkit` view; this only draws
// it and hands the typed answer back over the daemon socket, so the secret
// never becomes a process argument.
Item {
    id: root
    focus: true

    readonly property bool interactionAvailable: Ryoku.Polkit.active && !Ryoku.Polkit.busy
    // PAM says whether the answer may be shown as typed (a one-time code asks
    // with echo on); a secret stays masked.
    readonly property bool usePasswordChars: !Ryoku.Polkit.echo
    readonly property real d: IrisStyle.density

    // PAM's prompt doubles as the field label; its trailing ": " reads as a form
    // label in a card that already has a heading, so trim it.
    readonly property string fieldLabel: {
        const p = Ryoku.Polkit.prompt.trim()
        return p.length > 0 ? p.replace(/:\s*$/, "") : Translation.tr("Password")
    }

    function submit(): void {
        if (!root.interactionAvailable)
            return
        Ryoku.Polkit.submit(input.text)
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Ryoku.Polkit.cancel()
            event.accepted = true
        }
    }

    // A retry re-prompts in place; clear the stale answer and take focus again.
    Connections {
        target: Ryoku.Polkit
        function onRefreshed(): void {
            input.text = ""
            input.forceActiveFocus()
        }
    }

    property real shown: 0
    Component.onCompleted: { root.shown = 1; input.forceActiveFocus() }
    Behavior on shown { NumberAnimation { duration: IrisStyle.emergeDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: IrisStyle.emergeCurve } }

    Rectangle {
        anchors.fill: parent
        opacity: Math.min(1, root.shown)
        color: IrisStyle.scrim
    }

    IrisSurface {
        id: card
        anchors.centerIn: parent
        opacity: Math.min(1, root.shown * 1.6)
        scale: 1.08 - 0.08 * root.shown
        width: Math.min(320 * root.d, parent.width - 40)
        implicitHeight: body.implicitHeight + 40 * root.d
        radius: IrisStyle.radiusPlate
        raised: true

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 20 * root.d
            anchors.rightMargin: 20 * root.d
            spacing: 0

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: Math.round(52 * root.d)
                implicitHeight: implicitWidth
                radius: width / 2
                color: IrisStyle.tintFill(IrisStyle.accent)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "lock"
                    fill: 1
                    iconSize: Math.round(26 * root.d)
                    color: IrisStyle.accent
                }
            }
            IrisText {
                Layout.fillWidth: true
                Layout.topMargin: 14 * root.d
                horizontalAlignment: Text.AlignHCenter
                text: Ryoku.Polkit.message.length > 0
                    ? Ryoku.Polkit.message : Translation.tr("Authentication required")
                font.pixelSize: IrisStyle.typeHeadline
                font.weight: IrisStyle.weight(Font.DemiBold)
                wrapMode: Text.Wrap
            }
            IrisText {
                Layout.fillWidth: true
                Layout.topMargin: 6 * root.d
                visible: text.length > 0
                horizontalAlignment: Text.AlignHCenter
                text: Ryoku.Polkit.info
                color: IrisStyle.subtext
                font.pixelSize: IrisStyle.typeMeta
                wrapMode: Text.Wrap
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            IrisField {
                id: input
                Layout.fillWidth: true
                Layout.topMargin: 16 * root.d
                implicitHeight: Math.round(40 * root.d)
                focus: true
                enabled: root.interactionAvailable
                echoMode: root.usePasswordChars ? TextInput.Password : TextInput.Normal
                placeholderText: root.fieldLabel
                font.pixelSize: IrisStyle.typeBody
                onAccepted: root.submit()
                background: Rectangle {
                    radius: height / 2
                    color: (input.activeFocus ? IrisStyle.fill : IrisStyle.fillQuiet)
                    border.width: input.activeFocus ? Math.max(1, Math.round(1.5 * root.d)) : 0
                    border.color: IrisStyle.tintBorder(IrisStyle.accent)
                    Behavior on color { ColorAnimation { duration: IrisStyle.duration(120); easing.type: IrisStyle.feedbackEasing } }
                }
            }

            // A rejected attempt: PAM re-prompts in place, so the error sits above
            // the same field the retry is typed into.
            IrisText {
                Layout.fillWidth: true
                Layout.topMargin: 8 * root.d
                visible: Ryoku.Polkit.error.length > 0
                horizontalAlignment: Text.AlignHCenter
                text: Ryoku.Polkit.error
                color: IrisStyle.danger
                font.pixelSize: 11.5 * IrisStyle.typeScale
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 14 * root.d
                spacing: 8 * root.d
                IrisButton {
                    Layout.fillWidth: true
                    implicitHeight: Math.round(34 * root.d)
                    buttonRadius: height / 2
                    buttonRadiusPressed: height / 2
                    colBackground: IrisStyle.fill
                    colBackgroundHover: IrisStyle.fillHover
                    text: Translation.tr("Cancel")
                    onClicked: Ryoku.Polkit.cancel()
                }
                IrisButton {
                    Layout.fillWidth: true
                    implicitHeight: Math.round(34 * root.d)
                    buttonRadius: height / 2
                    buttonRadiusPressed: height / 2
                    emphasized: true
                    enabled: root.interactionAvailable
                    text: Ryoku.Polkit.busy ? Translation.tr("Checking…") : Translation.tr("Authenticate")
                    onClicked: root.submit()
                }
            }
        }
    }
}
