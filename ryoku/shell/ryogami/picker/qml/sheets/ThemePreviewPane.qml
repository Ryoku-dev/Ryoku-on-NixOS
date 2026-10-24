import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: pane

    property var palette: ({})
    property string editingRole: ""

    implicitHeight: 224 * Theme.scale
    implicitWidth: 360 * Theme.scale

    function _role(k) {
        var p = pane.palette
        return (p && typeof p[k] === "string" && p[k].length > 0) ? p[k] : Theme[k]
    }
    function _a(k, a) {
        var c = Qt.color(pane._role(k))
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    Rectangle {
        anchors.fill: parent
        color: pane._role("surface")
        border.width: 1
        border.color: pane._a("outline", 0.76)

        Row {
            anchors.fill: parent

            Rectangle {
                id: nav
                width: 126 * Theme.scale
                height: parent.height
                color: pane._role("background")
                border.width: 1
                border.color: pane._a("outline", 0.58)

                Column {
                    id: navTop
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 9 * Theme.scale
                    spacing: 6 * Theme.scale

                    Text {
                        text: I18n.tr("Settings index")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fs(9)
                        color: pane._role("surfaceText")
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        width: parent.width
                        height: 16 * Theme.scale
                        color: pane._role("surfaceContainer")
                        border.width: 1
                        border.color: pane._a("outline", 0.68)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 5 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u2312  " + I18n.tr("Search settings")
                            font.family: Theme.sans
                            font.pixelSize: Theme.fs(7)
                            color: pane._a("surfaceText", 0.6)
                            renderType: Text.NativeRendering
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 16 * Theme.scale
                        color: pane._role("surfaceVariant")
                        border.width: 1
                        border.color: pane._a("primary", 0.74)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 5 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u25cf  " + I18n.tr("Picker")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fs(7.5)
                            color: pane._role("surfaceText")
                            renderType: Text.NativeRendering
                        }
                    }

                    Repeater {
                        model: [I18n.tr("\u25cb  Motion"), I18n.tr("\u25cb  Playback"), I18n.tr("\u25cb  Theme")]
                        delegate: Text {
                            required property string modelData
                            leftPadding: 5 * Theme.scale
                            topPadding: 2 * Theme.scale
                            text: modelData
                            font.family: Theme.sans
                            font.pixelSize: Theme.fs(7.5)
                            color: pane._a("surfaceText", 0.68)
                            renderType: Text.NativeRendering
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 9 * Theme.scale
                    text: I18n.tr("Settings navigation")
                    font.family: Theme.sans
                    font.pixelSize: Theme.fs(7)
                    color: pane._a("surfaceText", 0.4)
                    renderType: Text.NativeRendering
                }
            }

            Rectangle {
                id: reading
                width: parent.width - nav.width
                height: parent.height
                color: pane._role("surface")

                Column {
                    anchors.fill: parent
                    anchors.margins: 11 * Theme.scale
                    spacing: 6 * Theme.scale

                    Text {
                        text: I18n.tr("Settings / theme")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fs(7)
                        color: pane._role("primary")
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: I18n.tr("Interface preview")
                        font.family: Theme.display
                        font.pixelSize: Theme.fs(15)
                        color: pane._role("surfaceText")
                        renderType: Text.NativeRendering
                    }
                    Text {
                        visible: pane.editingRole.length > 0
                        text: I18n.tr("Editing") + " " + pane.editingRole
                        font.family: Theme.sans
                        font.pixelSize: Theme.fs(7)
                        color: pane._a("surfaceText", 0.48)
                        renderType: Text.NativeRendering
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: pane._a("outline", 0.58)
                    }

                    Row {
                        width: parent.width
                        spacing: 7 * Theme.scale

                        Rectangle {
                            width: (parent.width - 7 * Theme.scale) / 2
                            height: 62 * Theme.scale
                            color: pane._role("surfaceContainer")
                            border.width: 1
                            border.color: pane._a("outline", 0.66)
                            Column {
                                anchors.fill: parent
                                anchors.margins: 6 * Theme.scale
                                spacing: 4 * Theme.scale
                                Text {
                                    text: I18n.tr("Primary control")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fs(8)
                                    color: pane._role("surfaceText")
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    width: parent.width
                                    text: I18n.tr("Selection, keyboard focus, and the main action.")
                                    wrapMode: Text.WordWrap
                                    font.family: Theme.sans
                                    font.pixelSize: Theme.fs(7)
                                    color: pane._a("surfaceText", 0.6)
                                    renderType: Text.NativeRendering
                                }
                                Rectangle {
                                    width: chipA.implicitWidth + 12 * Theme.scale
                                    height: 15 * Theme.scale
                                    color: pane._role("primary")
                                    border.width: 1
                                    border.color: pane._a("primary", 0.8)
                                    Text {
                                        id: chipA
                                        anchors.centerIn: parent
                                        text: I18n.tr("Selected")
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fs(7)
                                        color: pane._role("primaryText")
                                        renderType: Text.NativeRendering
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 7 * Theme.scale) / 2
                            height: 62 * Theme.scale
                            color: pane._role("surfaceVariant")
                            border.width: 1
                            border.color: pane._a("outline", 0.66)
                            Column {
                                anchors.fill: parent
                                anchors.margins: 6 * Theme.scale
                                spacing: 4 * Theme.scale
                                Text {
                                    text: I18n.tr("Alternate panel")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fs(8)
                                    color: pane._role("surfaceText")
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    width: parent.width
                                    text: I18n.tr("Secondary status and supporting information.")
                                    wrapMode: Text.WordWrap
                                    font.family: Theme.sans
                                    font.pixelSize: Theme.fs(7)
                                    color: pane._a("surfaceText", 0.6)
                                    renderType: Text.NativeRendering
                                }
                                Rectangle {
                                    width: chipB.implicitWidth + 12 * Theme.scale
                                    height: 15 * Theme.scale
                                    color: pane._role("surfaceContainer")
                                    border.width: 1
                                    border.color: pane._a("tertiary", 0.76)
                                    Text {
                                        id: chipB
                                        anchors.centerIn: parent
                                        text: I18n.tr("Secondary")
                                        font.family: Theme.sans
                                        font.weight: Font.Medium
                                        font.pixelSize: Theme.fs(7)
                                        color: pane._role("tertiary")
                                        renderType: Text.NativeRendering
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 17 * Theme.scale
                        color: pane._role("surface")
                        border.width: 1
                        border.color: pane._a("outline", 0.72)
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 6 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Filter wallpapers")
                            font.family: Theme.sans
                            font.pixelSize: Theme.fs(7)
                            color: pane._a("surfaceText", 0.62)
                            renderType: Text.NativeRendering
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: "/"
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fs(7)
                            color: pane._role("tertiary")
                            renderType: Text.NativeRendering
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 17 * Theme.scale
                        color: pane._role("surfaceContainer")
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 6 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5 * Theme.scale
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u25cf"
                                font.family: Theme.sans
                                font.pixelSize: Theme.fs(7)
                                color: pane._role("tertiary")
                                renderType: Text.NativeRendering
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("This palette is applied to the preview only")
                                font.family: Theme.sans
                                font.pixelSize: Theme.fs(7)
                                color: pane._a("surfaceText", 0.72)
                                renderType: Text.NativeRendering
                            }
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 6 * Theme.scale
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("9 roles")
                            font.family: Theme.display
                            font.pixelSize: Theme.fs(7)
                            color: pane._a("surfaceText", 0.72)
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }
        }
    }
}
