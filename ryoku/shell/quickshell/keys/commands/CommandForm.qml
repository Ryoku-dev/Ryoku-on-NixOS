pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    required property var store
    property bool opened: false
    property string mode: "add"
    property var entry: null
    property string message: ""

    signal closeRequested

    visible: opened || opacity > 0.001
    enabled: opened
    opacity: opened ? 1 : 0

    transform: Translate {
        x: root.opened ? 0 : Tokens.s3
        Behavior on x {
            enabled: !Tokens.reduceMotion
            NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
        }
    }

    Behavior on opacity {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.durSmall; easing.type: Easing.OutCubic }
    }

    function openAdd() {
        root.mode = "add";
        root.entry = null;
        nameField.text = "";
        commandField.text = "";
        descriptionField.text = "";
        tagsField.text = "";
        root.message = "";
        root.opened = true;
        Qt.callLater(commandField.grabFocus);
    }

    function openEdit(value) {
        root.mode = "edit";
        root.entry = value;
        nameField.text = value.name;
        commandField.text = value.command;
        descriptionField.text = value.description;
        tagsField.text = value.tags.join(", ");
        root.message = "";
        root.opened = true;
        Qt.callLater(nameField.grabFocus);
    }

    function close() {
        root.opened = false;
        root.closeRequested();
    }

    function parsedTags() {
        return tagsField.text.split(",").map(tag => tag.trim()).filter(tag => tag.length > 0);
    }

    function save() {
        const command = commandField.text.trim();
        if (command.length === 0) {
            root.message = I18n.tr("A command is required.");
            commandField.grabFocus();
            return;
        }
        const name = nameField.text.trim() || command;
        let saved = false;
        if (root.mode === "edit" && root.entry)
            saved = root.store.updateCommand(root.entry.id, name, command, descriptionField.text, root.parsedTags());
        else
            saved = root.store.addCommand(name, command, descriptionField.text, root.parsedTags());
        if (saved)
            root.close();
        else
            root.message = I18n.tr("The command could not be saved.");
    }

    Rectangle {
        anchors.fill: parent
        color: Tokens.paper
        border.width: Tokens.border
        border.color: Tokens.lineStrong
        radius: Tokens.radius

        TapHandler { acceptedButtons: Qt.AllButtons }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.s5
            spacing: Tokens.s4

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.s3

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.s1

                    Text {
                        text: root.mode === "edit" ? I18n.tr("EDIT COMMAND") : I18n.tr("NEW COMMAND")
                        color: Tokens.ink
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fMicro
                        font.letterSpacing: Tokens.trackMark
                    }

                    Text {
                        text: root.mode === "edit"
                            ? I18n.tr("Refine an entry in your library.")
                            : I18n.tr("Keep a command where you can find it again.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }
                }

                Btn {
                    text: I18n.tr("CANCEL")
                    onAct: root.close()
                }

                Btn {
                    text: I18n.tr("SAVE")
                    primary: true
                    armed: commandField.text.trim().length > 0
                    stealFocus: true
                    onAct: root.save()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.border
                color: Tokens.line
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2

                Text {
                    text: I18n.tr("NAME")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fTiny
                    font.letterSpacing: Tokens.trackLabel
                }
                Field {
                    id: nameField
                    Layout.fillWidth: true
                    placeholder: I18n.tr("A short, memorable name")
                    onAccepted: commandField.grabFocus()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2

                Text {
                    text: I18n.tr("COMMAND")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fTiny
                    font.letterSpacing: Tokens.trackLabel
                }
                Field {
                    id: commandField
                    Layout.fillWidth: true
                    tabular: true
                    placeholder: "git status --short --branch"
                    onAccepted: descriptionField.grabFocus()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2

                Text {
                    text: I18n.tr("DESCRIPTION")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fTiny
                    font.letterSpacing: Tokens.trackLabel
                }
                Field {
                    id: descriptionField
                    Layout.fillWidth: true
                    placeholder: I18n.tr("What this command is useful for")
                    onAccepted: tagsField.grabFocus()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2

                Text {
                    text: I18n.tr("TAGS")
                    color: Tokens.inkFaint
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fTiny
                    font.letterSpacing: Tokens.trackLabel
                }
                Field {
                    id: tagsField
                    Layout.fillWidth: true
                    placeholder: I18n.tr("Git, Development")
                    onAccepted: root.save()
                }
                Text {
                    text: I18n.tr("Separate tags with commas.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fTiny
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.message.length > 0
                text: root.message
                color: Tokens.alert
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
            }

            Item { Layout.fillHeight: true }

            Text {
                Layout.alignment: Qt.AlignRight
                text: I18n.tr("CTRL + ENTER  SAVE    ESC  CANCEL")
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
                font.letterSpacing: Tokens.trackLabel
            }
        }
    }

    Shortcut {
        enabled: root.opened
        sequences: ["Ctrl+Return", "Ctrl+Enter"]
        onActivated: root.save()
    }
}
