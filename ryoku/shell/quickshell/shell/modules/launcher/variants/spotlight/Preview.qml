// The Spotlight launcher's Ryoku Settings preview. Visual only: the variant
// takes no settings here; the frame's own settings overlay owns its knobs.

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Ryoku.Ui
import Ryoku.Ui.Singletons

Item {
    id: root

    property var settings: ({})
    signal editRequested(string key, var value)

    implicitWidth: 720
    implicitHeight: 250

    readonly property var rows: [
        { "icon": "\u{1F50D}", "name": "kitty", "detail": "Fast, feature-rich, GPU based terminal", "verb": "Launch" },
        { "icon": "\u26A1", "name": "toggle dark mode", "detail": "Switch the desktop theme", "verb": "Run" },
        { "icon": "\u{1F310}", "name": "kitty", "detail": "Search the web", "verb": "Open" }
    ]

    Rectangle {
        anchors.fill: parent
        color: Tokens.paper
    }

    Rectangle {
        id: palette

        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.s6, 460)
        height: 196
        radius: 26
        color: Tokens.paperLift
        border.color: Tokens.line
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.s4
            spacing: Tokens.s2

            // The search row: the query the palette morphs out of the island with.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                radius: 19
                color: Tokens.tint10
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.s3
                    anchors.rightMargin: Tokens.s3
                    spacing: Tokens.s2
                    Text {
                        text: "\u{1F50E}"
                        font.pixelSize: 13
                        color: Tokens.inkMuted
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "kitty"
                        font.pixelSize: 14
                        color: Tokens.ink
                    }
                    Rectangle {
                        Layout.preferredWidth: 2
                        Layout.preferredHeight: 16
                        radius: 1
                        color: Tokens.sun
                    }
                }
            }

            Repeater {
                model: root.rows
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    Layout.leftMargin: Tokens.s2
                    Layout.rightMargin: Tokens.s2
                    spacing: Tokens.s2

                    Rectangle {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        radius: 8
                        color: index === 0 ? Tokens.tint5 : Tokens.tint10
                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            font.pixelSize: 13
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: modelData.name
                            font.pixelSize: 13
                            font.bold: index === 0
                            color: Tokens.ink
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.detail
                            font.pixelSize: 10
                            color: Tokens.inkMuted
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }
                    Text {
                        text: modelData.verb
                        font.pixelSize: 10
                        color: Tokens.inkFaint
                    }
                }
            }
        }
    }
}
