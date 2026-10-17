pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import "TrayMenuGroup.js" as Group

/*
 * The right-click menu of an app tray icon, drawn in Karuma's own vocabulary
 * instead of the toolkit's default: the same paper PopupFrame as every hub
 * sheet, the palette's hover / press fills, the sheet radii and fonts, a seal
 * tint for checked items. Everything follows the palette, so a Matugen change
 * retints it with the bar.
 *
 * It renders the app's own menu (a QsMenuHandle) through QsMenuOpener, so
 * entries, separators, check / radio items, icons and submenus all come from
 * the app. Submenus open in place with a back row on top.
 */
PopupWindow {
    id: win

    required property var pal
    property real unit: 1
    // The icon the menu belongs to and the screen edge it opens away from.
    property Item anchorItem: null
    property int edges: Edges.Bottom
    // The application's menu handle (SystemTrayItem.menu).
    property var rootMenu: null
    // Submenu entries currently being browsed, outermost first.
    property var trail: []

    readonly property var current: trail.length > 0 ? trail[trail.length - 1] : rootMenu
    readonly property string currentTitle: trail.length > 0 ? String(trail[trail.length - 1].text || "") : ""

    function px(v) { return Math.round(v * win.unit) }
    // Opening one menu closes whichever other tray menu is still open.
    function open() { Group.claim(win); trail = []; visible = true }
    function close() { visible = false }
    onVisibleChanged: {
        if (visible) {
            if (win.pal.animate) fade.restart();
        } else {
            trail = [];
            Group.release(win);
        }
    }
    Component.onDestruction: Group.release(win)

    // Room around the paper for PopupFrame's soft shadow.
    readonly property real m: px(13)

    // Rows size to their text; the menu is as wide as its widest row.
    property real wantW: 0
    readonly property real menuW: Math.max(px(176), Math.min(px(360), wantW))
    function remeasure() {
        let w = back.implicitWidth;
        for (let i = 0; i < rows.count; ++i) {
            const it = rows.itemAt(i);
            if (it) w = Math.max(w, it.implicitWidth);
        }
        win.wantW = w;
    }

    anchor.item: win.anchorItem
    anchor.edges: win.edges
    anchor.gravity: win.edges
    anchor.adjustment: PopupAdjustment.All

    color: "transparent"
    grabFocus: true
    implicitWidth: frame.width + win.m * 2
    implicitHeight: frame.height + win.m * 2

    QsMenuOpener {
        id: opener
        menu: win.current
    }

    PopupFrame {
        id: frame
        x: win.m
        y: win.m
        pal: win.pal
        k: win.unit
        padding: 6
        width: col.width + inner * 2
        height: col.height + inner * 2

        NumberAnimation on opacity {
            id: fade
            running: false
            from: 0
            to: 1
            duration: 120
        }

        Column {
            id: col
            width: win.menuW
            spacing: win.px(1)

            // Back out of a submenu.
            Item {
                id: back
                visible: win.trail.length > 0
                width: parent.width
                height: visible ? win.px(30) : 0
                implicitWidth: win.px(10) + backGlyph.implicitWidth + win.px(8) + backText.implicitWidth + win.px(10)

                Rectangle {
                    anchors.fill: parent
                    radius: win.px(win.pal.radiusS + 2)
                    color: backArea.pressed ? win.pal.press : (backArea.containsMouse ? win.pal.hover : "transparent")
                    Behavior on color { enabled: win.pal.animate; ColorAnimation { duration: 100 } }
                }
                Text {
                    id: backGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: win.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u2039"
                    color: win.pal.inkMuted
                    font.family: win.pal.mono
                    font.pixelSize: win.px(15)
                }
                Text {
                    id: backText
                    anchors.left: backGlyph.right
                    anchors.leftMargin: win.px(8)
                    anchors.right: parent.right
                    anchors.rightMargin: win.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: win.currentTitle.length > 0 ? win.currentTitle : "Back"
                    color: win.pal.inkMuted
                    font.family: win.pal.mono
                    font.pixelSize: win.px(10)
                    font.bold: true
                    font.letterSpacing: win.px(0.8)
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.trail = win.trail.slice(0, win.trail.length - 1)
                }
                onImplicitWidthChanged: Qt.callLater(win.remeasure)
            }

            Repeater {
                id: rows
                model: opener.children
                onItemAdded: Qt.callLater(win.remeasure)
                onItemRemoved: Qt.callLater(win.remeasure)

                delegate: EntryRow {}
            }
        }
    }

    component EntryRow: Item {
        id: row
        required property var modelData

        readonly property bool isSep: modelData.isSeparator === true
        readonly property bool hasSub: modelData.hasChildren === true
        readonly property bool off: modelData.enabled === false
        readonly property bool isCheck: modelData.buttonType === QsMenuButtonType.CheckBox
        readonly property bool isRadio: modelData.buttonType === QsMenuButtonType.RadioButton
        readonly property bool checked: modelData.checkState === Qt.Checked
        readonly property string iconSource: String(modelData.icon || "")

        width: win.menuW
        height: isSep ? win.px(9) : win.px(30)
        implicitHeight: height
        implicitWidth: isSep ? 0
            : win.px(10) + win.px(20) + win.px(8) + label.implicitWidth + win.px(10) + (hasSub ? win.px(16) : 0)
        onImplicitWidthChanged: Qt.callLater(win.remeasure)

        // Separator: one soft hairline.
        Rectangle {
            visible: row.isSep
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: win.px(8)
            anchors.rightMargin: win.px(8)
            height: 1
            color: win.pal.lineSoft
        }

        // Hover / press plate.
        Rectangle {
            visible: !row.isSep
            anchors.fill: parent
            radius: win.px(win.pal.radiusS + 2)
            color: row.off ? "transparent"
                : (area.pressed ? win.pal.press : (area.containsMouse ? win.pal.hover : "transparent"))
            Behavior on color { enabled: win.pal.animate; ColorAnimation { duration: 100 } }
        }

        // Leading slot: check / radio badge, else the entry's icon.
        Item {
            id: lead
            visible: !row.isSep
            anchors.left: parent.left
            anchors.leftMargin: win.px(10)
            anchors.verticalCenter: parent.verticalCenter
            width: win.px(20)
            height: win.px(20)
            opacity: row.off ? 0.42 : 1

            Rectangle {
                visible: row.isCheck || row.isRadio
                anchors.centerIn: parent
                width: win.px(16)
                height: width
                radius: row.isRadio ? width / 2 : win.px(5)
                color: row.checked ? win.pal.seal : "transparent"
                border.width: 1
                border.color: row.checked ? win.pal.seal : win.pal.lineStrong
                Text {
                    visible: row.isCheck && row.checked
                    anchors.centerIn: parent
                    text: "\u2713"
                    color: win.pal.onSeal
                    font.family: win.pal.text
                    font.bold: true
                    font.pixelSize: win.px(11)
                }
                Rectangle {
                    visible: row.isRadio && row.checked
                    anchors.centerIn: parent
                    width: win.px(6)
                    height: width
                    radius: width / 2
                    color: win.pal.onSeal
                }
            }
            IconImage {
                visible: !(row.isCheck || row.isRadio) && row.iconSource.length > 0
                anchors.centerIn: parent
                implicitSize: win.px(16)
                source: row.iconSource
                mipmap: true
            }
        }

        Text {
            id: label
            visible: !row.isSep
            anchors.left: lead.right
            anchors.leftMargin: win.px(8)
            anchors.right: parent.right
            anchors.rightMargin: win.px(10) + (row.hasSub ? win.px(16) : 0)
            anchors.verticalCenter: parent.verticalCenter
            text: String(row.modelData.text || "")
            color: row.off ? win.pal.inkFaint : win.pal.ink
            font.family: win.pal.text
            font.pixelSize: win.px(12)
            elide: Text.ElideRight
        }

        Text {
            visible: row.hasSub
            anchors.right: parent.right
            anchors.rightMargin: win.px(10)
            anchors.verticalCenter: parent.verticalCenter
            text: "\u203A"
            color: win.pal.inkMuted
            font.family: win.pal.mono
            font.pixelSize: win.px(15)
        }

        MouseArea {
            id: area
            anchors.fill: parent
            enabled: !row.isSep && !row.off
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (row.hasSub) {
                    win.trail = win.trail.concat([row.modelData]);
                } else {
                    row.modelData.triggered();
                    win.close();
                }
            }
        }
    }
}
