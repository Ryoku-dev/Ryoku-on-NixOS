import QtQuick
import Qt.labs.folderlistmodel
import stage.services
import Ryoku.Ui.Singletons
import ".."

// A pinned folder's recent contents, opened by clicking the folder.
DockContextMenuBase {
    id: root

    property string folderPath: ""
    property int maxItems: 6

    readonly property string folderName: {
        if (!folderPath) return "";
        const parts = folderPath.split("/").filter(s => s.length > 0);
        return parts[parts.length - 1] ?? folderPath;
    }

    headerText: root.folderName
    headerSubtitle: root.folderPath
    headerSymbol: "folder_open"

    // Release the directory watcher with the popup. The list is small and
    // sorted locally as soon as the panel opens.
    FolderListModel {
        id: folderModel
        folder: root.menuOpen && root.folderPath ? ("file://" + root.folderPath) : ""
        showDirs: true
        showFiles: true
        showHidden: false
        showDotAndDotDot: false
        sortField: FolderListModel.Time
        sortReversed: true
    }

    menuGroups: {
        if (!root.menuOpen)
            return [];
        const files = [];
        const count = Math.min(folderModel.count, root.maxItems);
        for (let i = 0; i < count; i++) {
            const isDir = folderModel.get(i, "fileIsDir") ?? false;
            files.push({
                id: "file:" + i,
                icon: isDir ? "folder" : (root.anchorItem?.dockContent?.mimeIconFromPath(folderModel.get(i, "filePath") ?? "") ?? "insert_drive_file"),
                text: folderModel.get(i, "fileName") || ""
            });
        }
        return [files, [{ id: "openFolder", icon: "open_in_new", text: Translation.tr("Open in File Manager") }]];
    }

    onActionTriggered: actionId => {
        root.close();
        if (actionId === "openFolder") {
            Spawn.run(["xdg-open", root.folderPath]);
            return;
        }
        const index = parseInt(actionId.substring(5));
        const path = folderModel.get(index, "filePath")
            || (root.folderPath + "/" + (folderModel.get(index, "fileName") || ""));
        if (path)
            Spawn.run(["xdg-open", path]);
    }
}
