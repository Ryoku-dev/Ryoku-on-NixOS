pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

// Compatibility shapes used by the copied dock services, derived entirely
// from the neutral window-manager state.
Singleton {
    id: root

    readonly property var outputs: {
        const nativeOutputs = Wm.outputs || [];
        const workspaces = Wm.workspaces || [];
        const result = [];
        for (let i = 0; i < nativeOutputs.length; i++) {
            const output = nativeOutputs[i];
            let specialName = "";
            for (let j = 0; j < workspaces.length; j++) {
                const workspace = workspaces[j];
                if (workspace.special === true && workspace.active === true
                        && (workspace.output === "" || workspace.output === output.name)) {
                    specialName = workspace.name;
                    break;
                }
            }
            result.push({
                "name": output.name,
                "model": output.model ?? "",
                "make": output.make ?? "",
                "activeWorkspace": { "id": output.activeWorkspace ?? "" },
                "specialWorkspace": { "name": specialName }
            });
        }
        return result;
    }

    readonly property var windows: Wm.windows || []
    readonly property var focusedWorkspace: Wm.focusedWorkspace

    function toplevelOnScreen(toplevel) {
        if (!toplevel)
            return false;
        for (const window of root.windows) {
            if (window.toplevel === toplevel)
                return window.output !== "";
        }
        return true;
    }

    function outputHasFullscreen(name) {
        return Wm.outputHasFullscreen(name);
    }

    function clientsForWorkspace(workspaceId) {
        return Wm.windowsOnWorkspace(workspaceId);
    }
}
