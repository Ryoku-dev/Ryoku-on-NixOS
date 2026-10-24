pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import inir.modules.common
import inir.services

/**
 * Exposes the active keyboard layout name and short code for indicators.
 * The layout list and active layout come from the window-manager seam, so
 * this reads identically on every compositor the desktop supports; only the
 * name-to-code lookup is local (X11's base.lst).
 */
Singleton {
    id: root

    // You can read these
    readonly property list<string> layoutCodes: CompositorService.keyboardLayoutNames ?? []
    property var cachedLayoutCodes: ({})
    readonly property string currentLayoutName: CompositorService.getCurrentKeyboardLayoutName() ?? ""
    property string currentLayoutCode: ""

    property string baseLayoutFilePath: "/usr/share/X11/xkb/rules/base.lst"

    // Update the layout code according to the layout name (the seam gives the
    // descriptive name, the badge wants the short code).
    onCurrentLayoutNameChanged: root.updateLayoutCode()
    function updateLayoutCode() {
        if (cachedLayoutCodes.hasOwnProperty(currentLayoutName)) {
            root.currentLayoutCode = cachedLayoutCodes[currentLayoutName];
        } else {
            getLayoutProc.running = true;
        }
    }

    // Get the layout code from the base.lst file by grabbing the line with the current layout name
    Process {
        id: getLayoutProc
        command: ["cat", root.baseLayoutFilePath]

        stdout: StdioCollector {
            id: layoutCollector

            onStreamFinished: {
                const lines = layoutCollector.text.split("\n");
                const targetDescription = root.currentLayoutName;
                const foundLine = lines.find(line => {
                    // Skip comment lines and empty lines
                    if (!line.trim() || line.trim().startsWith('!'))
                        return false;

                    // Match layout: (whitespace + ) key + whitespace + description
                    const matchLayout = line.match(/^\s*(\S+)\s+(.+)$/);
                    if (matchLayout && matchLayout[2] === targetDescription) {
                        root.cachedLayoutCodes[matchLayout[2]] = matchLayout[1];
                        root.currentLayoutCode = matchLayout[1];
                        return true;
                    }

                    // Match variant: (whitespace + ) variant + whitespace + key + whitespace + description
                    const matchVariant = line.match(/^\s*(\S+)\s+(\S+)\s+(.+)$/);
                    if (matchVariant && matchVariant[3] === targetDescription) {
                        const complexLayout = matchVariant[2] + matchVariant[1];
                        root.cachedLayoutCodes[matchVariant[3]] = complexLayout;
                        root.currentLayoutCode = complexLayout;
                        return true;
                    }

                    return false;
                });
                if (!foundLine)
                    root.currentLayoutCode = root.currentLayoutName;
            }
        }
    }

    Component.onCompleted: root.updateLayoutCode()
}
