import QtQuick
import Quickshell
import Quickshell.Widgets
import Ryoku.Ui.Singletons
import stage.services
import "./widgets"
import "."

DockContextMenuBase {
    id: root

    property string filePath: ""

    readonly property string containingDir: {
        const idx = (filePath ?? "").lastIndexOf("/")
        return idx > 0 ? filePath.substring(0, idx) : ""
    }
    readonly property string xdgIcon: root.anchorItem?.resolvedXdgIcon ?? ""

    headerText: {
        const parts = (filePath ?? "").split("/").filter(s => s.length > 0)
        return parts[parts.length - 1] ?? filePath
    }
    headerSubtitle: root.filePath
    menuId: "dockFile"
    customTarget: root.filePath
    headerSymbol: root.anchorItem?.mimeIcon ?? "insert_drive_file"
    headerIcon: root.xdgIcon !== "" ? xdgIconComponent : null

    Component {
        id: xdgIconComponent
        IconImage {
            source: root.xdgIcon
            implicitSize: 48
        }
    }

    menuGroups: root.menuOpen ? [
        [
            { id: "open", icon: "open_in_new", text: Translation.tr("Open") },
            {
                id: "openContaining",
                icon: "folder_open",
                text: Translation.tr("Open containing folder"),
                visible: root.containingDir !== ""
            }
        ],
        [
            { id: "remove", icon: "do_not_disturb_on", text: Translation.tr("Remove from dock"), destructive: true }
        ]
    ] : []

    onActionTriggered: actionId => {
        if (actionId === "open")
            Spawn.runApp(["xdg-open", "file://" + root.filePath], { label: "file" })
        else if (actionId === "openContaining")
            Spawn.runApp(["xdg-open", "file://" + root.containingDir], { label: "folder" })
        else if (actionId === "remove")
            TaskbarApps.removePinnedFile(root.filePath)
        root.close()
    }
}
