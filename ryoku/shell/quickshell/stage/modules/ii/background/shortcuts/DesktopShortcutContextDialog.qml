pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import stage.services
import stage.modules.common
import stage.modules.common.widgets

ItemContextDialog {
    id: root
    required property var entry
    required property string screenName
    property string page: ""
    property string memberId: ""
    property string pendingAction: ""
    // >1 when the menu was opened on an icon inside a multi-selection: the
    // destructive action then speaks for the whole set, the rest for the
    // clicked entry alone.
    property int selectionCount: 1
    // The ids the selection pages act on: the whole selection when the menu
    // opened on a selected icon, else the clicked one alone.
    property var selectedIds: []
    // Other outputs the icons can be sent to.
    readonly property var otherScreens: Quickshell.screens.filter(s => s.name !== root.screenName)
    readonly property bool writable: Persistent.ready && !Persistent.blockWrites
    readonly property var member: (entry.apps ?? []).find(app => app.id === memberId) ?? null
    readonly property var otherFolders: DesktopShortcuts.folders(root.screenName)
        .filter(folder => folder.id !== root.entry.id)

    title: entry.name || entry.id || ""
    subtitle: root.selectionCount > 1 ? Translation.tr("%1 items selected").arg(String(root.selectionCount))
        : entry.path || (entry.type === "group"
            ? (entry.stack ? Translation.tr("Stack") : Translation.tr("Folder"))
            : entry.type === "url" ? Translation.tr("Web link") : Translation.tr("Application"))
    iconSource: Quickshell.iconPath(entry.icon || (entry.type === "group" ? "folder-applications"
        : entry.type === "directory" ? "folder"
        : entry.type === "url" ? "internet-web-browser" : "text-x-generic"), "image-missing")

    // Windows-like contextual actions. The source stays untouched: the
    // clipboard receives data via wl-copy with single-quote escaping.
    function copyText(text) {
        if (!text)
            return;
        Quickshell.execDetached(["bash", "-c", `printf '%s' '${StringUtils.shellSingleQuoteEscape(text)}' | wl-copy`]);
    }
    function revealInFolder() {
        const target = root.entry.path;
        if (!target)
            return;
        if (root.entry.type === "directory")
            Quickshell.execDetached(["xdg-open", target]);
        else
            Quickshell.execDetached(["xdg-open", target.substring(0, target.lastIndexOf("/") + 1) || "/"]);
        root.dismiss();
    }
    // A copy answers in place before the menu goes: the row fills, its icon
    // turns into a check and its label says so, long enough to be read.
    function confirmCopy(id) {
        root.confirmAction(id, Translation.tr("Copied"));
        copiedDismiss.restart();
    }
    Timer {
        id: copiedDismiss
        interval: 850
        onTriggered: root.dismiss()
    }

    // File managers expect a URI list; a web shortcut is already a URI.
    function copyItemReference() {
        const target = root.entry.path;
        if (!target)
            return;
        root.copyText(root.entry.type === "url" ? target
            : "file://" + encodeURI(target).replace(/#/g, "%23").replace(/\?/g, "%3F"));
    }
    actions: [
        { id: "open", text: entry.type === "group"
            ? (entry.stack ? Translation.tr("Open stack") : Translation.tr("Open folder"))
            : Translation.tr("Open"),
            icon: entry.type === "group" ? "apps" : "open_in_new", submenu: entry.type === "group" },
        { id: "rename", text: entry.type === "group"
            ? (entry.stack ? Translation.tr("Rename stack") : Translation.tr("Rename folder"))
            : Translation.tr("Rename shortcut"), icon: "edit", submenu: true, enabled: root.writable },
        { id: "details", text: Translation.tr("Details"), icon: "info", submenu: true },
        { id: "reveal", text: Translation.tr("Show in folder"), icon: "folder_open",
            visible: entry.path !== "" && entry.type !== "url" },
        { id: "copyName", text: Translation.tr("Copy name"), icon: "content_copy", visible: entry.name !== "" },
        { id: "copyPath", text: entry.type === "url" ? Translation.tr("Copy URL") : Translation.tr("Copy path"),
            icon: "content_paste", visible: entry.path !== "" },
        { id: "copyItem", text: Translation.tr("Copy"), icon: "file_copy", visible: entry.path !== "" },
        { id: "arrange", text: Translation.tr("Arrange selection"), icon: "align_horizontal_left",
            submenu: true, visible: root.selectionCount > 1, enabled: root.writable },
        { id: "screen", text: root.selectionCount > 1 ? Translation.tr("Move selection to screen")
            : Translation.tr("Move to screen"), icon: "screen_share",
            submenu: true, visible: root.otherScreens.length > 0, enabled: root.writable },
        { id: "remove", text: root.selectionCount > 1 ? Translation.tr("Remove selected items")
            : Translation.tr("Remove from desktop"), icon: "remove_circle_outline",
            destructive: true, enabled: root.writable }
    ].filter(action => action.visible !== false)
    pageComponent: page === "rename" ? renamePage : page === "members" ? membersPage
        : page === "add" ? addPage : page === "member" ? memberPage : page === "moveMember" ? moveMemberPage
        : page === "details" ? detailsPage : page === "arrange" ? arrangePage
        : page === "screen" ? screenPage : null
    pageDepth: page === "" ? 0
        : (page === "add" || page === "member" ? 2 : page === "moveMember" ? 3 : 1)
    onBackRequested: root.back()
    function back() {
        root.page = root.page === "moveMember" ? "member"
            : root.page === "add" || root.page === "member" ? "members" : "";
    }
    function launch(item) {
        DesktopShortcuts.launch(item);
        root.dismiss();
    }
    onActionTriggered: actionId => {
        if (actionId === "open") {
            if (root.entry.type === "group")
                root.page = "members";
            else
                root.launch(root.entry);
        } else if (actionId === "remove") {
            root.pendingAction = "remove";
            root.dismiss();
        } else if (actionId === "reveal") {
            root.revealInFolder();
        } else if (actionId === "copyName") {
            root.copyText(root.entry.name || "");
            root.confirmCopy(actionId);
        } else if (actionId === "copyPath") {
            root.copyText(root.entry.path || "");
            root.confirmCopy(actionId);
        } else if (actionId === "copyItem") {
            root.copyItemReference();
            root.confirmCopy(actionId);
        } else {
            root.page = actionId;
        }
    }

    component PageHeader: Item {
        id: header
        property string title: ""
        signal backRequested()
        Layout.fillWidth: true
        Layout.bottomMargin: Tokens.s1
        implicitHeight: Tokens.rowH

        IconBtn {
            id: backButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "‹"
            onAct: header.backRequested()
        }
        Text {
            anchors.left: backButton.right
            anchors.leftMargin: Tokens.s3
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: header.title
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fRow
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        onBackRequested: root.back()
    }

    component MenuField: Field {
        id: field
        property bool inputEnabled: true
        function focusField(selectAll: bool): void {
            field.grabFocus();
        }
        enabled: inputEnabled
        Layout.fillWidth: true
        toolbar: true
    }

    component MenuRow: Rectangle {
        id: menuRow
        property string symbol: ""
        property string title: ""
        property string subtitle: ""
        property url iconSource: ""
        property string trailingKind: "none"
        property bool destructive: false
        property bool rowEnabled: true
        property bool first: false
        property bool last: false
        signal activated()
        Layout.fillWidth: true
        implicitHeight: subtitle === "" ? Tokens.rowH : Tokens.rowH + Tokens.s3
        radius: Tokens.radius
        color: rowTap.pressed ? Tokens.tint16 : rowHover.hovered ? Tokens.tint10 : "transparent"
        border.width: activeFocus ? Tokens.border : 0
        border.color: Tokens.bone
        opacity: rowEnabled ? 1 : 0.4
        activeFocusOnTab: rowEnabled
        Behavior on color { ColorAnimation { duration: Tokens.snap } }

        Image {
            id: rowImage
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            width: Tokens.s5
            height: Tokens.s5
            sourceSize: Qt.size(width, height)
            source: menuRow.iconSource
            visible: source.toString().length > 0
            fillMode: Image.PreserveAspectFit
        }
        MaterialSymbol {
            id: rowSymbol
            anchors.centerIn: rowImage
            visible: !rowImage.visible
            text: menuRow.symbol
            iconSize: Tokens.s5
            color: menuRow.destructive ? Tokens.alert : Tokens.inkDim
        }
        Column {
            anchors.left: rowImage.right
            anchors.leftMargin: Tokens.s3
            anchors.right: rowTail.left
            anchors.rightMargin: Tokens.s2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.border
            Text {
                width: parent.width
                text: menuRow.title
                color: menuRow.destructive ? Tokens.alert : Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fBody
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: menuRow.subtitle !== ""
                text: menuRow.subtitle
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                elide: Text.ElideRight
            }
        }
        Text {
            id: rowTail
            anchors.right: parent.right
            anchors.rightMargin: Tokens.s3
            anchors.verticalCenter: parent.verticalCenter
            text: menuRow.trailingKind === "chevron" ? "›" : ""
            color: menuRow.destructive ? Tokens.alert : Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fBody
        }
        HoverHandler {
            id: rowHover
            enabled: menuRow.rowEnabled
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: rowTap
            enabled: menuRow.rowEnabled
            onTapped: menuRow.activated()
        }
        Keys.onPressed: event => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) && !event.isAutoRepeat) {
                menuRow.activated();
                event.accepted = true;
            }
        }
    }

    Component {
        id: renamePage
        ColumnLayout {
            spacing: Tokens.s1
            PageHeader {
                title: root.entry.type === "group"
                    ? (root.entry.stack ? Translation.tr("Rename stack") : Translation.tr("Rename folder"))
                    : Translation.tr("Rename shortcut")
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.s2
                Layout.bottomMargin: Tokens.s1
                text: root.entry.type === "group"
                    ? (root.entry.stack ? Translation.tr("Choose a name for this stack")
                        : Translation.tr("Choose a name for this folder"))
                    : Translation.tr("Only the shortcut label changes")
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                color: Tokens.inkMuted
            }
            MenuField {
                id: renameField
                Layout.bottomMargin: Tokens.s1
                text: root.entry.name || ""
                inputEnabled: root.writable
                onAccepted: saveName.activated()
                Component.onCompleted: renameField.focusField(true)
            }
            MenuRow {
                id: saveName
                symbol: "check"
                title: Translation.tr("Save")
                rowEnabled: root.writable && renameField.text.trim().length > 0
                onActivated: {
                    if (!rowEnabled)
                        return;
                    DesktopShortcuts.rename(root.screenName, root.entry.id, renameField.text);
                    root.page = "";
                }
            }
        }
    }
    Component {
        id: membersPage
        ColumnLayout {
            id: membersColumn
            spacing: Tokens.s1
            readonly property var apps: root.entry.apps ?? []
            PageHeader { title: root.entry.name || Translation.tr("Folder") }
            MenuRow {
                visible: !root.entry.stack || root.entry.stack === "app"
                symbol: "add"
                title: Translation.tr("Add apps")
                trailingKind: "chevron"
                first: true
                last: membersColumn.apps.length === 0
                rowEnabled: root.writable
                onActivated: root.page = "add"
            }
            Repeater {
                model: membersColumn.apps
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    title: modelData.name
                    iconSource: Quickshell.iconPath(modelData.icon, "image-missing")
                    trailingKind: "chevron"
                    first: false
                    last: index === membersColumn.apps.length - 1
                    onActivated: {
                        root.memberId = modelData.id;
                        root.page = "member";
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.margins: Tokens.s3
                visible: membersColumn.apps.length === 0
                text: Translation.tr("This folder is empty.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.Wrap
            }
        }
    }
    Component {
        id: memberPage
        ColumnLayout {
            spacing: Tokens.s1
            PageHeader { title: root.member?.name ?? "" }
            MenuRow {
                first: true
                last: false
                symbol: "open_in_new"
                title: Translation.tr("Open")
                rowEnabled: root.member !== null
                onActivated: root.launch(root.member)
            }
            MenuRow {
                first: false
                last: false
                visible: DesktopShortcuts.canTakeOut(root.screenName, root.entry.id)
                symbol: "drive_file_move"
                title: Translation.tr("Take out to the desktop")
                rowEnabled: root.writable && root.member !== null
                onActivated: {
                    DesktopShortcuts.takeOut(root.screenName, root.entry.id, root.memberId);
                    root.page = "members";
                }
            }
            MenuRow {
                first: false
                last: false
                symbol: "folder_copy"
                title: Translation.tr("Move to folder")
                trailingKind: "chevron"
                rowEnabled: root.writable && root.member !== null
                onActivated: root.page = "moveMember"
            }
            MenuRow {
                first: false
                last: true
                symbol: "remove_circle_outline"
                title: Translation.tr("Remove from desktop")
                destructive: true
                rowEnabled: root.writable && root.member !== null
                onActivated: {
                    DesktopShortcuts.removeApp(root.screenName, root.memberId);
                    root.page = "members";
                }
            }
        }
    }
    Component {
        id: moveMemberPage
        ColumnLayout {
            spacing: Tokens.s1
            PageHeader { title: Translation.tr("Move to folder") }
            Repeater {
                model: root.otherFolders
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    last: false
                    symbol: "folder"
                    title: modelData.name
                    subtitle: Translation.tr("%1 apps").arg(String(modelData.count))
                    onActivated: {
                        DesktopShortcuts.moveToFolder(root.screenName, root.entry.id,
                            root.memberId, modelData.id);
                        root.page = "members";
                    }
                }
            }
            MenuRow {
                first: root.otherFolders.length === 0
                last: true
                symbol: "create_new_folder"
                title: Translation.tr("New folder")
                onActivated: {
                    DesktopShortcuts.moveToFolder(root.screenName, root.entry.id,
                        root.memberId, "");
                    root.page = "members";
                }
            }
        }
    }
    Component {
        id: addPage
        ColumnLayout {
            spacing: Tokens.s1
            PageHeader { title: Translation.tr("Add apps") }
            DesktopShortcutAppPicker {
                Layout.fillWidth: true
                screenName: root.screenName
                folderId: root.entry.id
                refreshKey: root.entry
                onDone: root.page = "members"
            }
        }
    }
    Component {
        id: detailsPage
        ColumnLayout {
            spacing: Tokens.s1
            PageHeader { title: Translation.tr("Details") }
            // The item's identity as a static pill of the row's geometry
            // (circle + two lines), a whole run on its own.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(Tokens.rowH, detailsLayout.implicitHeight + Tokens.s4 * 2)
                radius: Tokens.radius
                color: Tokens.paperLift
                border.width: Tokens.border
                border.color: Tokens.line
                RowLayout {
                    id: detailsLayout
                    anchors.fill: parent
                    anchors.margins: Tokens.s4
                    spacing: Tokens.s3
                    Rectangle {
                        implicitWidth: Tokens.s7
                        implicitHeight: Tokens.s7
                        radius: Tokens.radius
                        color: Tokens.tint5
                        border.width: Tokens.border
                        border.color: Tokens.lineSoft
                        Image {
                            anchors.centerIn: parent
                            width: Tokens.s6
                            height: Tokens.s6
                            sourceSize: Qt.size(width, height)
                            source: root.iconSource
                            visible: source.toString().length > 0
                            fillMode: Image.PreserveAspectFit
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: root.iconSource.toString().length === 0
                            text: root.entry.type === "directory" ? "folder"
                                : root.entry.type === "file" ? "description"
                                : root.entry.type === "url" ? "language" : "apps"
                            iconSize: Tokens.s5
                            color: Tokens.ink
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.s1
                        Text {
                            Layout.fillWidth: true
                            text: root.entry.type === "group"
                                ? (root.entry.stack ? Translation.tr("Stack") : Translation.tr("Folder"))
                                : root.entry.type === "directory" ? Translation.tr("Folder")
                                : root.entry.type === "file" ? Translation.tr("File")
                                : root.entry.type === "url" ? Translation.tr("Web link") : Translation.tr("Application")
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            font.weight: Font.Medium
                            color: Tokens.ink
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.entry.path || root.entry.id || ""
                            font.family: Tokens.mono
                            font.pixelSize: Tokens.fTiny
                            color: Tokens.inkMuted
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }

    // A square tool button in the card's idiom, for the align strip.
    component ToolButton: Rectangle {
        id: tool
        property string symbol: ""
        property string tip: ""
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: Tokens.rowH
        radius: Tokens.radius
        color: toolTap.pressed ? Tokens.tint16 : toolHover.hovered ? Tokens.tint10 : Tokens.tint5
        border.width: Tokens.border
        border.color: toolHover.hovered ? Tokens.lineStrong : Tokens.line
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        MaterialSymbol {
            id: toolGlyph
            anchors.centerIn: parent
            text: tool.symbol
            iconSize: Tokens.s5
            color: Tokens.ink
            scale: toolTap.pressed ? 0.9 : 1
            Behavior on scale {
                NumberAnimation { duration: Tokens.snap; easing.type: Tokens.ease }
            }
        }
        HoverHandler {
            id: toolHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: toolTap
            onTapped: tool.clicked()
        }
    }

    Component {
        id: arrangePage
        ColumnLayout {
            spacing: Tokens.s1
            readonly property var ids: root.selectedIds
            PageHeader { title: Translation.tr("Arrange %1 items").arg(String(root.selectionCount)) }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.s2
                Layout.topMargin: Tokens.border * 2
                text: Translation.tr("Align")
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                color: Tokens.inkMuted
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.s2
                columns: 3
                rowSpacing: Tokens.s1
                columnSpacing: Tokens.s1
                Repeater {
                    model: [
                        { mode: "left", symbol: "align_horizontal_left", tip: Translation.tr("Align left") },
                        { mode: "hcenter", symbol: "align_horizontal_center", tip: Translation.tr("Align centers horizontally") },
                        { mode: "right", symbol: "align_horizontal_right", tip: Translation.tr("Align right") },
                        { mode: "top", symbol: "align_vertical_top", tip: Translation.tr("Align top") },
                        { mode: "vcenter", symbol: "align_vertical_center", tip: Translation.tr("Align centers vertically") },
                        { mode: "bottom", symbol: "align_vertical_bottom", tip: Translation.tr("Align bottom") }
                    ]
                    delegate: ToolButton {
                        required property var modelData
                        symbol: modelData.symbol
                        tip: modelData.tip
                        onClicked: DesktopShortcuts.alignSelection(root.screenName, root.selectedIds, modelData.mode)
                    }
                }
            }
            MenuRow {
                first: true
                last: false
                symbol: "horizontal_distribute"
                title: Translation.tr("Distribute horizontally")
                onActivated: DesktopShortcuts.distributeSelection(root.screenName, root.selectedIds, "horizontal")
            }
            MenuRow {
                first: false
                last: false
                symbol: "vertical_distribute"
                title: Translation.tr("Distribute vertically")
                onActivated: DesktopShortcuts.distributeSelection(root.screenName, root.selectedIds, "vertical")
            }
            MenuRow {
                first: false
                last: false
                symbol: "view_agenda"
                title: Translation.tr("Stack in a column")
                onActivated: DesktopShortcuts.stackSelection(root.screenName, root.selectedIds, "column")
            }
            MenuRow {
                first: false
                last: !groupRow.visible
                symbol: "view_column"
                title: Translation.tr("Stack in a row")
                onActivated: DesktopShortcuts.stackSelection(root.screenName, root.selectedIds, "row")
            }
            MenuRow {
                id: groupRow
                first: false
                last: true
                visible: DesktopShortcuts.canGroup(root.screenName, root.selectedIds)
                symbol: "create_new_folder"
                title: Translation.tr("Put in a new folder")
                onActivated: {
                    DesktopShortcuts.groupSelection(root.screenName, root.selectedIds);
                    root.dismiss();
                }
            }
        }
    }
    Component {
        id: screenPage
        ColumnLayout {
            spacing: Tokens.s1
            PageHeader { title: Translation.tr("Move to screen") }
            Repeater {
                model: root.otherScreens
                delegate: MenuRow {
                    required property var modelData
                    required property int index
                    first: index === 0
                    last: index === root.otherScreens.length - 1
                    symbol: "monitor"
                    title: modelData.name
                    subtitle: modelData.model ?? ""
                    trailingKind: "chevron"
                    onActivated: {
                        const ids = root.selectedIds.length > 0 ? root.selectedIds : [root.entry.id];
                        const from = root.screenName;
                        const to = modelData.name;
                        root.dismiss();
                        Qt.callLater(() => DesktopShortcuts.moveToScreen(from, to, ids));
                    }
                }
            }
        }
    }
}
