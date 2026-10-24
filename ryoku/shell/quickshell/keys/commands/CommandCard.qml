pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Ryoku.Ui
import Ryoku.Ui.Singletons

Rectangle {
    id: root

    required property var entry
    property bool copied: false
    property bool selected: false
    property int animationDelay: 0
    property bool entered: Tokens.reduceMotion
    property bool entranceReady: false
    readonly property bool hasPlaceholder: /<[^<>\s](?:[^<>]*[^<>\s])?>/.test(String(root.entry.command || ""))
    readonly property bool hasUsageSyntax: root.hasPlaceholder
        || /[\[\]|…]/.test(String(root.entry.command || ""))
        || String(root.entry.command || "").indexOf("...") >= 0
    readonly property bool canRun: !root.hasUsageSyntax && root.entry.danger !== true
    readonly property var badges: {
        const result = [];
        if (root.entry.privileged === true)
            result.push({ label: I18n.tr("Needs password"), alert: false, quiet: false });
        if (root.entry.danger === true)
            result.push({ label: I18n.tr("Careful"), alert: true, quiet: false });
        if (root.entry.level === "advanced")
            result.push({ label: I18n.tr("Advanced"), alert: false, quiet: true });
        if (String(root.entry.onlyOn || "").length > 0)
            result.push({ label: I18n.tr("Only on %1").arg(root.entry.onlyOn), alert: false, quiet: false });
        if (String(root.entry.requires || "").length > 0)
            result.push({ label: I18n.tr("Needs %1").arg(root.entry.requires), alert: false, quiet: false });
        return result;
    }

    signal copyRequested
    signal runRequested
    signal editRequested
    signal deleteRequested
    signal favouriteRequested
    signal selectedRequested

    function escapeMarkup(value) {
        return String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;");
    }

    function commandMarkup() {
        const command = String(root.entry.command || "");
        let cursor = 0;
        let result = "";
        const pattern = /<[^<>\s](?:[^<>]*[^<>\s])?>/g;
        let match = pattern.exec(command);
        while (match) {
            result += root.escapeMarkup(command.slice(cursor, match.index));
            result += "<b><u>" + root.escapeMarkup(match[0]) + "</u></b>";
            cursor = match.index + match[0].length;
            match = pattern.exec(command);
        }
        return result + root.escapeMarkup(command.slice(cursor));
    }

    function restartEntrance() {
        if (Tokens.reduceMotion) {
            root.entered = true;
            return;
        }
        root.entered = false;
        entranceTimer.restart();
    }

    Component.onCompleted: {
        root.entranceReady = true;
        root.restartEntrance();
    }
    onEntryChanged: {
        if (root.entranceReady)
            root.restartEntrance();
    }

    implicitHeight: content.implicitHeight + Tokens.s4 * 2
    radius: Tokens.radius
    opacity: root.entered ? 1 : 0
    scale: cardTap.pressed ? 0.992 : 1
    color: hover.hovered ? Tokens.tint5 : "transparent"
    border.width: Tokens.border
    border.color: root.selected || hover.hovered ? Tokens.lineStrong : Tokens.line

    transform: Translate {
        y: root.entered ? 0 : Tokens.s2
        Behavior on y {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
    }

    Behavior on opacity {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.snap; easing.type: Tokens.easeSnap }
    }
    Behavior on color {
        enabled: !Tokens.reduceMotion
        ColorAnimation { duration: Tokens.snap }
    }
    Behavior on border.color {
        enabled: !Tokens.reduceMotion
        ColorAnimation { duration: Tokens.snap }
    }

    Timer {
        id: entranceTimer
        interval: root.animationDelay
        onTriggered: root.entered = true
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: cardTap
        acceptedButtons: Qt.LeftButton
        onTapped: root.selectedRequested()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Tokens.s4
        spacing: Tokens.s3

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.s2

            Text {
                Layout.fillWidth: true
                text: root.entry.title || root.entry.name
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fRow
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Btn {
                compact: true
                text: root.copied ? I18n.tr("✓ COPIED") : I18n.tr("COPY")
                primary: root.copied
                onAct: root.copyRequested()
            }

            Btn {
                compact: true
                text: root.entry.favourite ? I18n.tr("★ STARRED") : I18n.tr("☆ STAR")
                primary: root.entry.favourite
                onAct: root.favouriteRequested()
            }

            Btn {
                visible: root.canRun
                compact: true
                text: I18n.tr("RUN")
                onAct: root.runRequested()
            }

            Btn {
                visible: root.entry.source === "user"
                compact: true
                text: I18n.tr("EDIT")
                onAct: root.editRequested()
            }

            Btn {
                visible: root.entry.source === "user"
                compact: true
                text: I18n.tr("DELETE")
                onAct: root.deleteRequested()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: commandText.implicitHeight + Tokens.s3 * 2
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineSoft

            Text {
                id: commandText
                anchors.fill: parent
                anchors.margins: Tokens.s3
                text: root.commandMarkup()
                textFormat: Text.RichText
                color: Tokens.ink
                font.family: Tokens.mono
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WrapAnywhere
                verticalAlignment: Text.AlignVCenter
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.s2
            visible: root.badges.length > 0

            Repeater {
                model: root.badges

                delegate: Rectangle {
                    id: badge
                    required property var modelData
                    width: badgeLabel.implicitWidth + Tokens.s3 * 2
                    height: badgeLabel.implicitHeight + Tokens.s2
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: badge.modelData.alert ? Tokens.alert : Tokens.line

                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: badge.modelData.label
                        color: badge.modelData.alert ? Tokens.alert
                            : (badge.modelData.quiet ? Tokens.inkFaint : Tokens.inkMuted)
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fTiny
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: String(root.entry.description || "").length > 0
            text: root.entry.description
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }
    }
}
