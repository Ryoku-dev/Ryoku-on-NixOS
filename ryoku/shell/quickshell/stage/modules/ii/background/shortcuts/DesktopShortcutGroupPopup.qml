pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Ryoku.Ui
import Ryoku.Ui.Singletons
import stage.services
import stage.modules.common
import stage.modules.common.widgets

FocusScope {
    id: root

    required property var entry
    required property rect tileRect
    required property string screenName
    property bool showPicker: false
    property real counterScale: 1
    property real reveal: 0
    property bool closing: false
    property bool renaming: false
    property string memberMenuPage: ""
    property string memberMenuId: ""
    property point memberMenuPoint: Qt.point(0, 0)

    signal closeRequested()
    signal renameRequested(string name)
    signal ungroupRequested()
    signal takeOutRequested(string appId)
    signal moveRequested(string appId, string folderId)
    signal removeRequested(string appId)
    signal disableStacksRequested()

    readonly property var apps: entry.apps ?? []
    readonly property int columns: Math.max(1, Math.min(3, apps.length))
    readonly property real cellWidth: Tokens.s7 + Tokens.s6
    readonly property int gridRows: Math.ceil(apps.length / columns)
    readonly property var memberMenuEntry: apps.find(app => app.id === memberMenuId) ?? null
    readonly property var otherFolders: DesktopShortcuts.folders(screenName)
        .filter(folder => folder.id !== entry.id)
    readonly property bool canTakeOut: DesktopShortcuts.canTakeOut(screenName, entry.id)
    readonly property bool acceptsApps: !entry.stack || entry.stack === "app"
    readonly property real bodySpan: 0.22
    readonly property real plateSpan: 0.22
    readonly property real rowLead: 0.2
    readonly property real rowSpan: 0.55

    function ease(t: real): real {
        return t * t * (3 - 2 * t);
    }

    readonly property real bodyReveal: root.ease(Math.min(1, reveal / bodySpan))
    readonly property real plateReveal: root.ease(Math.min(1, reveal / plateSpan))
    readonly property bool opensDownward: card.y > tileRect.y + tileRect.height / 2

    function rowReveal(index: int, count: int): real {
        const step = count > 1
            ? Math.min(0.041, (1 - root.rowLead - root.rowSpan) / (count - 1)) : 0;
        const t = (root.reveal - root.rowLead - index * step) / root.rowSpan;
        return root.ease(Math.max(0, Math.min(1, t)));
    }

    function dismiss() {
        if (closing)
            return;
        closing = true;
        revealMotion.stop();
        revealMotion.to = 0;
        revealMotion.start();
    }

    function launch(app) {
        DesktopShortcuts.launch(app);
        root.dismiss();
    }

    function beginRename() {
        root.showPicker = false;
        root.memberMenuPage = "";
        root.renaming = true;
        renameField.text = root.entry.name || "";
        Qt.callLater(() => renameField.grabFocus());
    }

    function saveRename() {
        const name = renameField.text.trim();
        if (name.length > 0 && name !== (root.entry.name || ""))
            root.renameRequested(name);
        root.renaming = false;
        root.forceActiveFocus();
    }

    function openMemberMenu(memberId, point) {
        root.showPicker = false;
        root.renaming = false;
        root.memberMenuId = memberId;
        root.memberMenuPage = "actions";
        root.memberMenuPoint = point;
    }

    function closeMemberMenu() {
        root.memberMenuPage = "";
        root.memberMenuId = "";
    }

    onAppsChanged: {
        if (root.memberMenuId !== "" && !root.memberMenuEntry)
            root.closeMemberMenu();
    }

    focus: true
    Component.onCompleted: {
        if (!root.showPicker)
            root.forceActiveFocus();
        revealMotion.start();
    }
    Keys.onEscapePressed: event => {
        event.accepted = true;
        if (root.renaming) {
            root.renaming = false;
            root.forceActiveFocus();
        } else if (root.memberMenuPage !== "") {
            root.closeMemberMenu();
        } else if (root.showPicker) {
            root.showPicker = false;
            root.forceActiveFocus();
        } else {
            root.dismiss();
        }
    }

    NumberAnimation {
        id: revealMotion
        target: root
        property: "reveal"
        to: 1
        duration: Tokens.reduceMotion ? 0 : (root.closing ? Tokens.snap : Tokens.move)
        easing.type: Tokens.ease
        onFinished: {
            if (root.closing)
                root.closeRequested();
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: root.dismiss()
        onWheel: wheel => wheel.accepted = true
    }

    component CardAction: Rectangle {
        id: action
        property string symbol: ""
        property string label: ""
        property bool destructive: false
        property bool actionEnabled: true
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: Tokens.rowH
        radius: Tokens.radius
        color: actionTap.pressed ? Tokens.tint16
            : actionHover.hovered ? Tokens.tint10 : "transparent"
        opacity: actionEnabled ? 1 : 0.45
        activeFocusOnTab: actionEnabled

        MaterialSymbol {
            id: actionGlyph
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            text: action.symbol
            iconSize: Tokens.s5
            color: action.destructive ? Tokens.alert : Tokens.inkDim
        }
        Text {
            anchors.left: actionGlyph.right
            anchors.leftMargin: Tokens.s3
            anchors.right: parent.right
            anchors.rightMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            text: action.label
            color: action.destructive ? Tokens.alert : Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fBody
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        HoverHandler {
            id: actionHover
            enabled: action.actionEnabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: actionTap
            enabled: action.actionEnabled
            onTapped: action.triggered()
        }
        Keys.onPressed: event => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) && !event.isAutoRepeat) {
                action.triggered();
                event.accepted = true;
            }
        }
    }

    Rectangle {
        id: card
        readonly property real gap: Tokens.s2

        // Placement runs in the card's own unscaled space: the desktop shrinks
        // while editing and the card undoes it, so the room it has is the
        // layer's extent divided by the same factor.
        x: {
            const k = root.counterScale;
            const ts = root.tileRect;
            return Math.max(card.gap, Math.min(root.width / k - width - card.gap,
                (ts.x + ts.width / 2) / k - width / 2)) * k;
        }
        y: {
            const k = root.counterScale;
            const room = root.height / k;
            const tileY = root.tileRect.y / k;
            const tileHeight = root.tileRect.height / k;
            const below = tileY + tileHeight + card.gap;
            const wanted = below + implicitHeight + card.gap > room
                ? tileY - implicitHeight - card.gap : below;
            return Math.max(card.gap, Math.min(room - implicitHeight - card.gap, wanted)) * k;
        }
        width: Math.min(root.width / root.counterScale - 2 * card.gap,
            Math.max(Tokens.railW + Tokens.s6,
                root.columns * root.cellWidth + (root.columns - 1) * Tokens.s1 + Tokens.s5))
        height: implicitHeight
        implicitHeight: cardLayout.implicitHeight + Tokens.s5
        radius: Tokens.radius
        color: Tokens.paper
        border.width: Tokens.border
        border.color: Tokens.line
        opacity: Math.min(1, root.reveal * 8)
        scale: root.counterScale * (0.94 + 0.06 * root.bodyReveal)
        transformOrigin: Item.TopLeft
        transform: Translate {
            y: (1 - root.bodyReveal) * (root.opensDownward ? -Tokens.s3 : Tokens.s3)
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            id: cardLayout
            anchors.fill: parent
            anchors.margins: Tokens.s3
            anchors.topMargin: Tokens.s2
            spacing: Tokens.s2

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.s1
                Layout.rightMargin: Tokens.s1
                spacing: Tokens.s2
                opacity: root.plateReveal

                Item {
                    Layout.preferredWidth: Tokens.s6
                    Layout.preferredHeight: Tokens.s6
                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: Tokens.border * 2
                        Repeater {
                            model: root.apps.slice(0, 4)
                            delegate: IconImage {
                                required property var modelData
                                implicitSize: Tokens.fMicro
                                source: Quickshell.iconPath(modelData.icon, "image-missing")
                            }
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: root.apps.length === 0
                        text: "folder"
                        iconSize: Tokens.s5
                        color: Tokens.inkDim
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.border
                    visible: !root.renaming
                    Text {
                        Layout.fillWidth: true
                        text: root.entry.name || root.entry.id || ""
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fBody
                        font.weight: Font.Medium
                        color: Tokens.ink
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.entry.stack && root.entry.stack !== "app"
                            ? (root.apps.length === 1 ? Translation.tr("1 item")
                                : Translation.tr("%1 items").arg(String(root.apps.length)))
                            : root.apps.length === 1 ? Translation.tr("1 app")
                                : Translation.tr("%1 apps").arg(String(root.apps.length))
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fTiny
                        color: Tokens.inkMuted
                        elide: Text.ElideRight
                    }
                }

                Field {
                    id: renameField
                    Layout.fillWidth: true
                    visible: root.renaming
                    toolbar: true
                    onAccepted: root.saveRename()
                    Keys.onEscapePressed: event => {
                        root.renaming = false;
                        root.forceActiveFocus();
                        event.accepted = true;
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.s1
                visible: !root.showPicker

                Btn {
                    compact: true
                    primary: true
                    visible: root.acceptsApps
                    text: Translation.tr("Add apps")
                    onAct: {
                        root.renaming = false;
                        root.closeMemberMenu();
                        root.showPicker = true;
                    }
                }
                Btn {
                    compact: true
                    text: root.renaming ? Translation.tr("Save") : Translation.tr("Rename")
                    onAct: root.renaming ? root.saveRename() : root.beginRename()
                }
                Btn {
                    compact: true
                    visible: !root.entry.stack
                    text: Translation.tr("Dissolve folder")
                    onAct: root.ungroupRequested()
                }
            }

            DesktopShortcutAppPicker {
                Layout.fillWidth: true
                visible: root.showPicker && root.acceptsApps
                screenName: root.screenName
                folderId: root.entry.id
                refreshKey: root.entry
                onDone: {
                    root.showPicker = false;
                    root.forceActiveFocus();
                }
            }

            Flickable {
                id: appFlickable
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(Tokens.railW, appGrid.implicitHeight)
                visible: !root.showPicker && root.apps.length > 0
                contentHeight: appGrid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                TouchpadScrollHandler {
                    flickable: appFlickable
                }
                GridLayout {
                    id: appGrid
                    width: parent.width
                    columns: root.columns
                    columnSpacing: Tokens.s1
                    rowSpacing: Tokens.s1

                    Repeater {
                        model: root.apps
                        delegate: Rectangle {
                            id: memberCell
                            required property var modelData
                            required property int index
                            readonly property real arrived: root.rowReveal(
                                Math.floor(index / root.columns), root.gridRows)

                            Layout.preferredWidth: (appGrid.width
                                - (root.columns - 1) * appGrid.columnSpacing) / root.columns
                            Layout.preferredHeight: Tokens.s7 + Tokens.s6
                            radius: Tokens.radius
                            color: memberTap.pressed ? Tokens.tint16
                                : memberHover.hovered ? Tokens.tint10 : "transparent"
                            border.width: memberHover.hovered ? Tokens.border : 0
                            border.color: Tokens.lineStrong
                            activeFocusOnTab: true
                            opacity: arrived
                            scale: 0.965 + 0.035 * arrived
                            transformOrigin: Item.TopLeft

                            Behavior on color {
                                ColorAnimation { duration: Tokens.snap }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: Tokens.s1
                                IconImage {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.topMargin: Tokens.s2
                                    implicitSize: Tokens.s6
                                    source: Quickshell.iconPath(memberCell.modelData.icon, "image-missing")
                                }
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Tokens.s1
                                    Layout.rightMargin: Tokens.s1
                                    text: memberCell.modelData.name || memberCell.modelData.id
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            Rectangle {
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Tokens.s1
                                visible: memberHover.hovered && root.canTakeOut
                                height: Tokens.s5
                                width: takeOutText.implicitWidth + Tokens.s2
                                radius: height / 2
                                color: Tokens.bone
                                border.width: Tokens.border
                                border.color: Tokens.bone
                                z: 2
                                Text {
                                    id: takeOutText
                                    anchors.centerIn: parent
                                    text: Translation.tr("Take out")
                                    color: Tokens.inkOnBone
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fTiny
                                }
                                TapHandler {
                                    onTapped: {
                                        root.takeOutRequested(memberCell.modelData.id);
                                        root.closeMemberMenu();
                                    }
                                }
                            }

                            HoverHandler {
                                id: memberHover
                                cursorShape: Qt.PointingHandCursor
                            }
                            TapHandler {
                                id: memberTap
                                acceptedButtons: Qt.LeftButton
                                onTapped: root.launch(memberCell.modelData)
                            }
                            TapHandler {
                                acceptedButtons: Qt.RightButton
                                onTapped: event => {
                                    const point = memberCell.mapToItem(card,
                                        event.position.x, event.position.y);
                                    root.openMemberMenu(memberCell.modelData.id, point);
                                }
                            }
                            Keys.onReturnPressed: root.launch(memberCell.modelData)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.showPicker && root.apps.length === 0
                spacing: Tokens.s2

                Text {
                    Layout.fillWidth: true
                    text: Translation.tr("This folder is empty.")
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    color: Tokens.inkMuted
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
                Btn {
                    Layout.alignment: Qt.AlignHCenter
                    compact: true
                    visible: root.acceptsApps
                    text: Translation.tr("Add apps")
                    onAct: root.showPicker = true
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !root.showPicker && !!root.entry.stack
                    && (DesktopShortcuts.options.stacks ?? false)
                implicitHeight: stackFooter.implicitHeight + Tokens.s4
                radius: Tokens.radius
                color: Tokens.tint5
                border.width: Tokens.border
                border.color: Tokens.line

                ColumnLayout {
                    id: stackFooter
                    anchors.fill: parent
                    anchors.margins: Tokens.s2
                    spacing: Tokens.s2
                    Text {
                        Layout.fillWidth: true
                        text: root.entry.stack === "directory"
                            ? Translation.tr("Stacks gather loose folders automatically.")
                            : root.entry.stack === "file"
                                ? Translation.tr("Stacks gather loose files automatically.")
                                : Translation.tr("Stacks gather loose apps automatically.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        wrapMode: Text.Wrap
                    }
                    Btn {
                        Layout.alignment: Qt.AlignRight
                        compact: true
                        text: Translation.tr("Turn off stacks")
                        onAct: root.disableStacksRequested()
                    }
                }
            }
        }

        Rectangle {
            id: memberMenu
            visible: root.memberMenuPage !== "" && root.memberMenuEntry !== null
            enabled: visible
            z: 20
            width: Math.min(card.width - Tokens.s4, Tokens.railW)
            height: Math.min(memberMenuLayout.implicitHeight + Tokens.s4,
                Math.max(Tokens.rowH + Tokens.s4, card.height - Tokens.s4))
            x: Math.max(Tokens.s2, Math.min(card.width - width - Tokens.s2,
                root.memberMenuPoint.x))
            y: Math.max(Tokens.s2, Math.min(card.height - height - Tokens.s2,
                root.memberMenuPoint.y))
            radius: Tokens.radius
            color: Tokens.paperLift
            border.width: Tokens.border
            border.color: Tokens.lineStrong

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Flickable {
                id: memberMenuScroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: memberMenuLayout.implicitHeight + Tokens.s4
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                TouchpadScrollHandler {
                    flickable: memberMenuScroll
                }

                ColumnLayout {
                    id: memberMenuLayout
                    x: Tokens.s2
                    y: Tokens.s2
                    width: memberMenuScroll.width - Tokens.s4
                    spacing: Tokens.s1

                    CardAction {
                        visible: root.memberMenuPage === "actions"
                        symbol: "open_in_new"
                        label: Translation.tr("Open")
                        onTriggered: root.launch(root.memberMenuEntry)
                    }
                    CardAction {
                        visible: root.memberMenuPage === "actions" && root.canTakeOut
                        symbol: "drive_file_move"
                        label: Translation.tr("Take out")
                        onTriggered: {
                            root.takeOutRequested(root.memberMenuId);
                            root.closeMemberMenu();
                        }
                    }
                    CardAction {
                        visible: root.memberMenuPage === "actions"
                        symbol: "folder_copy"
                        label: Translation.tr("Move to folder")
                        onTriggered: root.memberMenuPage = "move"
                    }
                    CardAction {
                        visible: root.memberMenuPage === "actions"
                        symbol: "remove_circle_outline"
                        label: Translation.tr("Remove from desktop")
                        destructive: true
                        onTriggered: {
                            root.removeRequested(root.memberMenuId);
                            root.closeMemberMenu();
                        }
                    }

                    CardAction {
                        visible: root.memberMenuPage === "move"
                        symbol: "arrow_back"
                        label: Translation.tr("Back")
                        onTriggered: root.memberMenuPage = "actions"
                    }
                    Repeater {
                        model: root.memberMenuPage === "move" ? root.otherFolders : []
                        delegate: CardAction {
                            required property var modelData
                            symbol: "folder"
                            label: modelData.name
                            onTriggered: {
                                root.moveRequested(root.memberMenuId, modelData.id);
                                root.closeMemberMenu();
                            }
                        }
                    }
                    CardAction {
                        visible: root.memberMenuPage === "move"
                        symbol: "create_new_folder"
                        label: Translation.tr("New folder")
                        onTriggered: {
                            root.moveRequested(root.memberMenuId, "");
                            root.closeMemberMenu();
                        }
                    }
                }
            }
        }
    }
}
