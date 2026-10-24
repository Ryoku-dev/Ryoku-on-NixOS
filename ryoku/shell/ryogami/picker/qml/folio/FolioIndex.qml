import QtQuick
import QtQuick.Controls as QQC
import Ryoku.Ui.Singletons
import "FolioSearch.js" as Search

FolioIndexShell {
    id: nav

    property var tabs: []
    property int activeTabIndex: 0
    property int activeSectionIndex: 0
    property bool searchOpen: false
    property string query: ""

    signal selectTab(int tabIndex)
    signal selectSection(int tabIndex, int sectionIndex)
    signal openResult(int tabIndex, int sectionIndex, string controlId)
    signal searchToggled(bool open)
    signal queryEdited(string text)

    title: I18n.tr("Settings index")
    note: (nav.activeTabIndex >= 0 && nav.activeTabIndex < nav.tabs.length) ? nav.tabs[nav.activeTabIndex].note : ""
    bodySpacing: 17

    readonly property var _results: (nav.searchOpen && nav.query.length > 0) ? Search.search(nav.query, nav.tabs) : []
    onSearchOpenChanged: if (nav.searchOpen) searchInput.forceActiveFocus()

    Column {
        parent: nav.body
        width: nav.body.width
        spacing: 9 * Theme.scale

        Rectangle {
            id: searchBox
            width: parent.width
            height: 30 * Theme.scale
            color: searchArea.containsMouse && !nav.searchOpen
                ? Theme.withAlpha(Theme.surfaceVariant, 0.62 * nav.reveal) : "transparent"

            Row {
                visible: !nav.searchOpen
                anchors.fill: parent
                anchors.leftMargin: 8 * Theme.scale
                anchors.rightMargin: 8 * Theme.scale
                spacing: 8 * Theme.scale

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2315"
                    font.family: Theme.sans
                    font.pixelSize: Theme.fontLead
                    color: Theme.withAlpha(Theme.surfaceText, 0.55)
                    renderType: Text.NativeRendering
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 120 * Theme.scale
                    text: I18n.tr("Search settings")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontWide
                    color: Theme.withAlpha(Theme.surfaceText, nav.reveal)
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                }
            }
            Text {
                visible: !nav.searchOpen
                anchors.right: parent.right
                anchors.rightMargin: 8 * Theme.scale
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Ctrl F")
                font.family: Theme.sans
                font.weight: Font.Medium
                font.pixelSize: Theme.fontFine
                color: Theme.withAlpha(Theme.surfaceText, 0.42 * nav.reveal)
                renderType: Text.NativeRendering
            }
            MouseArea {
                id: searchArea
                anchors.fill: parent
                hoverEnabled: true
                visible: !nav.searchOpen
                cursorShape: Qt.PointingHandCursor
                onClicked: nav.searchToggled(true)
            }

            Row {
                visible: nav.searchOpen
                anchors.fill: parent
                spacing: 7 * Theme.scale
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2315"
                    font.family: Theme.sans
                    font.pixelSize: Theme.fontLead
                    color: Theme.withAlpha(Theme.surfaceText, 0.55)
                    renderType: Text.NativeRendering
                }
                TextField {
                    id: searchInput
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 60 * Theme.scale
                    variant: "ghost"
                    placeholder: I18n.tr("Search settings")
                    text: nav.query
                    onEdited: (t) => nav.queryEdited(t)
                    onCommitted: {
                        if (nav._results.length > 0) {
                            var r = nav._results[0];
                            nav.openResult(r.tabIndex, r.sectionIndex, r.controlId);
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u00d7"
                    font.family: Theme.sans
                    font.pixelSize: Theme.fontField
                    color: Theme.withAlpha(Theme.surfaceText, closeArea.containsMouse ? 0.9 : 0.55)
                    renderType: Text.NativeRendering
                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -6 * Theme.scale
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { nav.queryEdited(""); nav.searchToggled(false); }
                    }
                }
            }
            Component.onCompleted: if (nav.searchOpen) searchInput.forceActiveFocus()
        }

        Loader {
            width: parent.width
            height: nav.body.height - y - 4 * Theme.scale
            sourceComponent: (nav.searchOpen && nav.query.length > 0) ? resultsComp : treeComp
        }
    }

    Component {
        id: resultsComp
        Flickable {
            id: rflick
            contentWidth: width
            contentHeight: rcol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded; visible: false }

            Column {
                id: rcol
                width: rflick.width
                spacing: 1

                Text {
                    width: parent.width
                    visible: nav._results.length === 0
                    padding: 8 * Theme.scale
                    text: I18n.tr("No matching settings")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontXSmall
                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                }

                Repeater {
                    model: nav._results
                    delegate: Rectangle {
                        id: rrow
                        required property var modelData
                        width: rcol.width
                        height: rtext.implicitHeight + 16 * Theme.scale
                        color: rArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.07) : "transparent"

                        Column {
                            id: rtext
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 8 * Theme.scale
                            anchors.rightMargin: 8 * Theme.scale
                            spacing: 2 * Theme.scale
                            Text {
                                width: parent.width
                                text: rrow.modelData.title
                                font.family: Theme.sans
                                font.weight: Font.DemiBold
                                font.pixelSize: Theme.fontBody
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }
                            Text {
                                width: parent.width
                                text: rrow.modelData.tabLabel + "  /  " + rrow.modelData.sectionTitle
                                font.family: Theme.sans
                                font.weight: Font.Medium
                                font.pixelSize: Theme.fontFine
                                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                elide: Text.ElideRight
                                renderType: Text.NativeRendering
                            }
                        }
                        MouseArea {
                            id: rArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: nav.openResult(rrow.modelData.tabIndex, rrow.modelData.sectionIndex, rrow.modelData.controlId)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: treeComp
        Row {
            id: treeRow
            spacing: 9 * Theme.scale

            Flickable {
                id: tflick
                width: treeRow.width - rail.width - treeRow.spacing
                height: treeRow.height
                contentWidth: width
                contentHeight: tree.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded; visible: false }

                Column {
                    id: tree
                    width: tflick.width
                    spacing: 1

                    Repeater {
                        model: nav.tabs
                        delegate: Column {
                            id: cat
                            required property var modelData
                            required property int index
                            width: tree.width
                            readonly property bool _active: cat.index === nav.activeTabIndex

                            Rectangle {
                                width: parent.width
                                height: catText.implicitHeight + 16 * Theme.scale
                                radius: Theme.radius
                                color: cat._active ? Theme.withAlpha(Theme.surfaceText, 0.09 * nav.reveal)
                                    : (catArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06 * nav.reveal) : "transparent")

                                Row {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 8 * Theme.scale
                                    anchors.rightMargin: 8 * Theme.scale
                                    spacing: 8 * Theme.scale
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cat._active ? "\u25be" : (I18n.rtl ? "\u25c2" : "\u25b8")
                                        font.family: Theme.sans
                                        font.pixelSize: Theme.fontSmall
                                        color: Theme.withAlpha(Theme.surfaceText, cat._active ? 0.85 : 0.55)
                                        renderType: Text.NativeRendering
                                    }
                                    Text {
                                        id: catText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: cat.modelData.title
                                        font.family: Theme.sans
                                        font.weight: cat._active ? Font.DemiBold : Font.Medium
                                        font.pixelSize: Theme.fontBody2
                                        color: Theme.withAlpha(Theme.surfaceText, nav.reveal)
                                        elide: Text.ElideRight
                                        renderType: Text.NativeRendering
                                    }
                                }
                                MouseArea {
                                    id: catArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: nav.selectTab(cat.index)
                                }
                            }

                            Item {
                                width: parent.width
                                clip: true
                                height: cat._active ? branchLoader.implicitHeight : 0
                                Behavior on height { NumberAnimation { duration: Theme.fast; easing.type: Theme.revealEasing } }

                                Rectangle {
                                    visible: cat._active
                                    x: I18n.rtl ? parent.width - width : 12 * Theme.scale
                                    width: 1
                                    height: parent.height
                                    color: Theme.withAlpha(Theme.surfaceText, 0.18 * nav.reveal)
                                }

                                // Collapsed categories never build their section rows, so the first
                                // open lays out only the open category's branch.
                                Loader {
                                    id: branchLoader
                                    width: parent.width
                                    active: cat._active
                                    sourceComponent: branchComp
                                }
                                Component {
                                    id: branchComp
                                    Column {
                                        id: branch
                                        width: branchLoader.width
                                        Repeater {
                                            model: cat.modelData.sections
                                            delegate: Rectangle {
                                                id: sec
                                                required property var modelData
                                                required property int index
                                                width: branch.width
                                                height: 36 * Theme.scale
                                                radius: Theme.radius
                                                readonly property bool _active: cat._active && sec.index === nav.activeSectionIndex
                                                color: sec._active ? Theme.withAlpha(Theme.surfaceText, nav.reveal)
                                                    : (secArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.07 * nav.reveal) : "transparent")

                                                Text {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: 24 * Theme.scale
                                                    anchors.rightMargin: 10 * Theme.scale
                                                    text: sec.modelData.title
                                                    font.family: Theme.sans
                                                    font.weight: sec._active ? Font.DemiBold : Font.Medium
                                                    font.pixelSize: Theme.fontWide
                                                    color: sec._active ? Theme.surface : Theme.withAlpha(Theme.surfaceText, nav.reveal * 0.72)
                                                    elide: Text.ElideRight
                                                    renderType: Text.NativeRendering
                                                }
                                                MouseArea {
                                                    id: secArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: nav.selectSection(cat.index, sec.index)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            IndexRail {
                id: rail
                height: treeRow.height
                count: nav.tabs.length
                activeIndex: nav.activeTabIndex
                reveal: nav.reveal
            }
        }
    }
}
