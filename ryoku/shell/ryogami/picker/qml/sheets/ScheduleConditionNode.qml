import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: node

    property var sheet: null
    property var model: null
    property var path: []
    property int depth: 0

    readonly property bool isGroup: node.model !== null && node.model.block === undefined
    readonly property bool isRoot: node.depth === 0
    readonly property var _editing: node.sheet ? node.sheet.editing : ({ mode: "none", path: [] })
    readonly property bool selected: node._editing.mode === "node"
        && node.sheet && node.sheet.pathEquals(node._editing.path, node.path)
    readonly property bool addActive: node._editing.mode === "add"
        && node.sheet && node.sheet.pathEquals(node._editing.path, node.path)

    implicitWidth: 200 * Theme.scale
    implicitHeight: col.implicitHeight

    Column {
        id: col
        width: node.width
        spacing: 4 * Theme.scale

        Item {
            width: parent.width
            height: nodeBox.height
            x: node.depth * 13 * Theme.scale

            Rectangle {
                id: nodeBox
                width: parent.width - node.depth * 13 * Theme.scale
                height: nodeContent.implicitHeight + 16 * Theme.scale
                radius: Theme.radius
                color: node.selected ? Theme.surfaceText
                                     : Theme.withAlpha(Theme.surfaceContainer, 0.22)
                border.width: 1
                border.color: node.selected ? "transparent"
                                            : Theme.withAlpha(Theme.outline, 0.3)
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Behavior on border.color { ColorAnimation { duration: Theme.fast } }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 9 * Theme.scale
                    anchors.rightMargin: 9 * Theme.scale
                    anchors.topMargin: 8 * Theme.scale
                    anchors.bottomMargin: 8 * Theme.scale
                    spacing: 8 * Theme.scale

                    Column {
                        id: nodeContent
                        width: parent.width - editLabel.width - parent.spacing
                        spacing: 2 * Theme.scale

                        Text {
                            width: parent.width
                            text: node.sheet ? node.sheet.nodeEyebrow(node.model, node.isRoot) : ""
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fs(7.8)
                            color: node.selected ? Theme.withAlpha(Theme.surface, 0.72)
                                                 : Theme.withAlpha(Theme.surfaceText, 0.5)
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: node.sheet ? (node.isGroup ? node.sheet.groupTitle(node.model)
                                                              : node.sheet.conditionSentence(node.model)) : ""
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontBase
                            color: node.selected ? Theme.surface : Theme.surfaceText
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: node.sheet ? (node.isGroup ? node.sheet.groupDetail(node.model)
                                                              : node.sheet.predicateDetail(node.model)) : ""
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fs(8.6)
                            color: node.selected ? Theme.withAlpha(Theme.surface, 0.68)
                                                 : Theme.withAlpha(Theme.surfaceText, 0.44)
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: editLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: node.selected ? I18n.tr("Editing") : I18n.tr("Edit  \u203a")
                        font.family: Theme.sans
                        font.weight: Font.Medium
                        font.pixelSize: Theme.fontFine
                        color: node.selected ? Theme.withAlpha(Theme.surface, 0.8)
                                             : Theme.withAlpha(Theme.surfaceText, 0.5)
                        renderType: Text.NativeRendering
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (node.sheet) node.sheet.editNode(node.path)
                }
            }
        }

        Repeater {
            model: node.isGroup ? node.model.children.length : 0

            delegate: Column {
                id: childWrap
                required property int index
                width: col.width
                spacing: 3 * Theme.scale

                Text {
                    x: (node.depth + 1) * 13 * Theme.scale
                    text: node.sheet ? node.sheet.connector(childWrap.index, node.model.op) : ""
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fs(8)
                    color: Theme.withAlpha(Theme.surfaceText, 0.4)
                    renderType: Text.NativeRendering
                }

                // QML refuses a type that declares itself, so a nested node loads by URL.
                Loader {
                    id: childLoader
                    width: parent.width
                    source: Qt.resolvedUrl("ScheduleConditionNode.qml")
                    onLoaded: {
                        item.sheet = Qt.binding(() => node.sheet)
                        item.model = Qt.binding(() => node.model.children[childWrap.index])
                        item.path = Qt.binding(() => node.path.concat([childWrap.index]))
                        item.depth = Qt.binding(() => node.depth + 1)
                    }
                }
            }
        }

        Item {
            visible: node.isGroup
            width: parent.width
            height: node.isGroup ? addAction.height : 0
            x: (node.depth + 1) * 13 * Theme.scale

            FolioAction {
                id: addAction
                width: parent.width - (node.depth + 1) * 13 * Theme.scale
                fixedWidth: parent.width - (node.depth + 1) * 13 * Theme.scale
                label: I18n.tr("Add condition or group")
                glyph: "\uf067"
                active: node.addActive
                onTriggered: if (node.sheet) node.sheet.editAdd(node.path)
            }
        }
    }
}
