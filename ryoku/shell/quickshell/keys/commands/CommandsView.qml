pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "."

Item {
    id: root

    required property var controller
    required property var store
    property string query: ""
    property string railCurrent: "group:ryoku:start"
    property bool active: false
    property string copiedId: ""
    property bool appeared: Tokens.reduceMotion
    readonly property bool shortcutsEnabled: root.active && !form.opened && !importPicker.active
    readonly property bool managingCommands: root.query.length === 0
        && root.controller.railLibrary(root.railCurrent) === "saved"
        && root.controller.railGroup(root.railCurrent) === "my-commands"

    readonly property var rows: {
        const catalogRevision = root.controller.catalogRevision;
        const storeRevision = root.store.revision;
        return root.controller.displayRows(root.query, root.railCurrent);
    }

    opacity: root.appeared ? 1 : 0
    transform: Translate {
        x: root.appeared ? 0 : Tokens.s2
        Behavior on x {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
    }
    Behavior on opacity {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
    }

    Component.onCompleted: {
        if (!Tokens.reduceMotion)
            appearTimer.start();
    }

    Timer {
        id: appearTimer
        interval: 1
        onTriggered: root.appeared = true
    }

    signal requestClose

    function activate() {
        if (form.opened)
            return;
        list.forceActiveFocus();
    }

    function openAdd() {
        root.controller.railCurrent = "group:saved:my-commands";
        form.openAdd();
    }

    function openImport() {
        root.controller.railCurrent = "group:saved:my-commands";
        importPicker.open();
    }

    function handleEscape() {
        if (importPicker.active) {
            importPicker.active = false;
            return true;
        }
        if (form.opened) {
            form.close();
            return true;
        }
        return false;
    }

    function selectedEntry() {
        if (list.currentIndex < 0 || list.currentIndex >= root.rows.length)
            return null;
        return root.rows[list.currentIndex].entry;
    }

    function copy(entry) {
        if (!entry)
            return;
        Quickshell.clipboardText = entry.command;
        root.copiedId = entry.id;
        copiedTimer.restart();
    }

    function run(entry) {
        if (!entry)
            return;
        Spawn.run(["ryoku-app", "terminal", "--", "/usr/bin/bash", "-lc", entry.command]);
        root.requestClose();
    }

    function edit(entry) {
        if (entry && entry.source === "user")
            form.openEdit(entry);
    }

    function remove(entry) {
        if (entry && entry.source === "user") {
            root.store.deleteCommand(entry.id);
            list.currentIndex = Math.min(list.currentIndex, root.rows.length - 1);
        }
    }

    onRowsChanged: {
        if (root.rows.length === 0)
            list.currentIndex = -1;
        else if (list.currentIndex < 0 || list.currentIndex >= root.rows.length)
            list.currentIndex = 0;
        list.contentY = 0;
        if (!Tokens.reduceMotion)
            countPulse.restart();
    }

    SequentialAnimation {
        id: countPulse
        NumberAnimation {
            target: countLabel
            property: "opacity"
            to: 0.45
            duration: Tokens.snap
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: countLabel
            property: "opacity"
            to: 1
            duration: Tokens.snap
            easing.type: Easing.OutCubic
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.s3

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.s3

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1

                Text {
                    text: root.query.length > 0
                        ? I18n.tr("SEARCH RESULTS")
                        : root.controller.selectionLabel().toUpperCase()
                    color: Tokens.ink
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                    font.letterSpacing: Tokens.trackMark
                }

                Text {
                    id: countLabel
                    text: {
                        const count = root.rows.length;
                        if (root.query.length > 0)
                            return I18n.tr(count === 1 ? "%1 entry matching “%2”" : "%1 entries matching “%2”").arg(count).arg(root.query);
                        return I18n.tr(count === 1 ? "%1 entry" : "%1 entries").arg(count);
                    }
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                }
            }

            Text {
                visible: root.store.saving || root.store.notice.length > 0
                text: root.store.notice.length > 0 ? root.store.notice.toUpperCase() : I18n.tr("SAVING")
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
                font.letterSpacing: Tokens.trackLabel
            }

            Btn {
                visible: root.managingCommands && root.rows.length > 0
                text: I18n.tr("IMPORT")
                onAct: root.openImport()
            }

            Btn {
                visible: root.managingCommands && root.rows.length > 0
                text: I18n.tr("＋ ADD COMMAND")
                primary: true
                onAct: root.openAdd()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.border
            color: Tokens.line
        }

        Text {
            Layout.fillWidth: true
            visible: root.store.error.length > 0
            text: root.store.error
            color: Tokens.alert
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: Tokens.s4
                boundsBehavior: Flickable.StopAtBounds
                activeFocusOnTab: true
                model: root.rows
                currentIndex: root.rows.length > 0 ? 0 : -1
                reuseItems: true
                QQC.ScrollBar.vertical: ScrollRail {
                    policy: QQC.ScrollBar.AsNeeded
                    visible: list.contentHeight > list.height + 1
                }
                WheelScroll { }

                delegate: Item {
                    id: rowDelegate
                    required property var modelData
                    required property int index
                    width: ListView.view.width - Tokens.s2
                    implicitHeight: rowContent.implicitHeight

                    Column {
                        id: rowContent
                        width: parent.width
                        spacing: Tokens.s3

                        Text {
                            visible: root.query.length > 0 && rowDelegate.modelData.firstLibrary
                            text: rowDelegate.modelData.libraryLabel.toUpperCase()
                            color: Tokens.ink
                            font.family: Tokens.display
                            font.pixelSize: Tokens.fValue
                        }

                        Row {
                            visible: root.query.length > 0 && rowDelegate.modelData.firstGroup
                            spacing: Tokens.s2

                            Rectangle {
                                width: 18
                                height: Tokens.border
                                color: Tokens.inkMuted
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: rowDelegate.modelData.groupLabel.toUpperCase()
                                color: Tokens.inkMuted
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fMicro
                                font.letterSpacing: Tokens.trackLabel
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: cautionText.implicitHeight + Tokens.s3 * 2
                            visible: rowDelegate.modelData.firstGroup
                                && rowDelegate.modelData.groupId === "ryoku-internal"
                            color: Tokens.tint5
                            border.width: Tokens.border
                            border.color: Tokens.line
                            radius: Tokens.radius

                            Text {
                                id: cautionText
                                anchors.fill: parent
                                anchors.margins: Tokens.s3
                                text: I18n.tr("Ryoku runs these itself. You rarely need them by hand.")
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                wrapMode: Text.WordWrap
                            }
                        }

                        CommandCard {
                            id: card
                            width: parent.width
                            entry: rowDelegate.modelData.entry
                            animationDelay: Math.min(rowDelegate.index, 6) * 24
                            copied: root.copiedId === rowDelegate.modelData.entry.id
                            selected: rowDelegate.ListView.isCurrentItem
                            onSelectedRequested: list.currentIndex = rowDelegate.index
                            onCopyRequested: root.copy(card.entry)
                            onRunRequested: root.run(card.entry)
                            onEditRequested: root.edit(card.entry)
                            onDeleteRequested: root.remove(card.entry)
                            onFavouriteRequested: root.store.toggleFavourite(card.entry.id)
                        }
                    }
                }
            }

            Column {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.rightMargin: Tokens.s2
                anchors.topMargin: Tokens.s4
                spacing: Tokens.s4
                visible: root.controller.ready && root.rows.length === 0

                Text {
                    width: parent.width
                    text: {
                        if (root.query.length > 0)
                            return I18n.tr("Nothing matches “%1”.").arg(root.query);
                        const group = root.controller.railGroup(root.railCurrent);
                        if (group === "favourites")
                            return I18n.tr("Star any command to keep it here.");
                        if (group === "my-commands")
                            return I18n.tr("Add your own commands, or import a JSON list.");
                        return I18n.tr("No commands are filed here yet.");
                    }
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }

                Row {
                    spacing: Tokens.s2
                    visible: root.managingCommands

                    Btn {
                        text: I18n.tr("＋ ADD COMMAND")
                        primary: true
                        onAct: root.openAdd()
                    }

                    Btn {
                        text: I18n.tr("IMPORT")
                        onAct: root.openImport()
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.controller.ready
                text: I18n.tr("LOADING COMMANDS")
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro
                font.letterSpacing: Tokens.trackLabel
            }
        }

        Text {
            Layout.alignment: Qt.AlignRight
            text: I18n.tr("CTRL + N  NEW    CTRL + I  IMPORT    ↑↓  SELECT    CTRL + ENTER  COPY")
            color: Tokens.inkFaint
            font.family: Tokens.mono
            font.pixelSize: Tokens.fTiny
            font.letterSpacing: Tokens.trackLabel
        }
    }

    CommandForm {
        id: form
        anchors.fill: parent
        z: 20
        store: root.store
        onCloseRequested: list.forceActiveFocus()
    }

    PickFile {
        id: importPicker
        fileFilters: ["*.json"]
        title: I18n.tr("Import commands")
        emptyText: I18n.tr("No JSON command libraries here")
        startFolder: "file://" + (Quickshell.env("HOME") || "") + "/Downloads"
        onPicked: path => {
            importPicker.active = false;
            root.store.importCommands(path);
        }
        onCanceled: importPicker.active = false
    }

    Timer {
        id: copiedTimer
        interval: 1700
        onTriggered: root.copiedId = ""
    }

    Shortcut {
        enabled: root.shortcutsEnabled
        sequence: "Ctrl+N"
        onActivated: root.openAdd()
    }

    Shortcut {
        enabled: root.shortcutsEnabled
        sequence: "Ctrl+I"
        onActivated: root.openImport()
    }

    Shortcut {
        enabled: root.shortcutsEnabled && root.rows.length > 0
        sequence: "Down"
        onActivated: {
            list.currentIndex = Math.min(root.rows.length - 1, list.currentIndex + 1);
            list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        }
    }

    Shortcut {
        enabled: root.shortcutsEnabled && root.rows.length > 0
        sequence: "Up"
        onActivated: {
            list.currentIndex = Math.max(0, list.currentIndex - 1);
            list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        }
    }

    Shortcut {
        enabled: root.shortcutsEnabled && root.selectedEntry() !== null
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        onActivated: root.copy(root.selectedEntry())
    }

    Shortcut {
        enabled: root.shortcutsEnabled && root.selectedEntry()?.source === "user"
        sequence: "Ctrl+E"
        onActivated: root.edit(root.selectedEntry())
    }

    Shortcut {
        enabled: root.shortcutsEnabled && root.selectedEntry()?.source === "user"
        sequence: "Ctrl+D"
        onActivated: root.remove(root.selectedEntry())
    }
}
