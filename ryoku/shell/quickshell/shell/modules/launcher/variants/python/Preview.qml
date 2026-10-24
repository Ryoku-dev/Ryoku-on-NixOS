// Python's launcher preview for Ryoku Settings. Visual only: the bar-attached
// search pill with its app rows and the Files tab switch, drawn in the style's
// dark palette. Nothing here is editable.

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

    readonly property color bg: "#1e1e2e"
    readonly property color pill: "#313244"
    readonly property color pillHi: "#45475a"
    readonly property color accent: "#cba6f7"
    readonly property color ink: "#cdd6f4"
    readonly property color dim: "#a6adc8"

    Rectangle {
        anchors.fill: parent
        color: "#11111b"
    }

    // the bar strip the pill attaches under
    Rectangle {
        id: bar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Tokens.s4
        height: 26
        radius: 13
        color: root.bg

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Repeater {
                model: 5
                Rectangle {
                    width: index === 0 ? 18 : 9
                    height: 9
                    radius: 5
                    color: index === 0 ? root.accent : root.pillHi
                }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "21:26"
            color: root.ink
            font.family: Tokens.mono
            font.pixelSize: Tokens.fSmall
        }
    }

    // the launcher pill, docked under the bar's left edge
    Rectangle {
        id: pill
        anchors.top: bar.bottom
        anchors.topMargin: 4
        anchors.left: bar.left
        anchors.leftMargin: Tokens.s6
        width: 300
        height: 150
        radius: 16
        color: root.bg
        border.color: Qt.alpha(root.pillHi, 0.6)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 20
                    radius: 10
                    color: root.pill
                    Text {
                        anchors.centerIn: parent
                        text: "Apps"
                        color: root.accent
                        font.family: Tokens.ui
                        font.pixelSize: 9
                        font.bold: true
                    }
                }
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 20
                    radius: 10
                    color: "transparent"
                    border.color: root.pillHi
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "Files"
                        color: root.dim
                        font.family: Tokens.ui
                        font.pixelSize: 9
                    }
                }
                Item { Layout.fillWidth: true }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                radius: 8
                color: root.pill
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    spacing: 5
                    Text {
                        text: "⌕"
                        color: root.dim
                        font.pixelSize: 11
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "firefox"
                        color: root.ink
                        font.family: Tokens.ui
                        font.pixelSize: 10
                    }
                }
            }

            Repeater {
                model: [
                    { name: "Firefox", desc: "Web Browser" },
                    { name: "Files", desc: "File Manager" }
                ]
                delegate: Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 8
                    color: index === 0 ? Qt.alpha(root.accent, 0.16) : "transparent"
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 7
                        Rectangle {
                            Layout.preferredWidth: 14
                            Layout.preferredHeight: 14
                            radius: 4
                            color: index === 0 ? root.accent : root.pillHi
                        }
                        Text {
                            text: modelData.name
                            color: root.ink
                            font.family: Tokens.ui
                            font.pixelSize: 10
                            font.bold: index === 0
                        }
                        Text {
                            Layout.fillWidth: true
                            text: modelData.desc
                            color: root.dim
                            font.family: Tokens.ui
                            font.pixelSize: 8
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
