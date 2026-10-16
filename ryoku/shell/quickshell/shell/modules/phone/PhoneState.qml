pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property alias activeDeviceId: state.activeDeviceId
    property alias recentDeviceIds: state.recentDeviceIds
    property alias favoriteContactIds: state.favoriteContactIds
    property alias favoritePackages: state.favoritePackages
    property alias recentPackages: state.recentPackages
    property alias notificationCache: state.notificationCache

    // Set by PhoneBridge after the package-status probe. Phone services use
    // this runtime gate so merely loading the bridge never starts helpers.
    property bool runtimeReady: false

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku"
    readonly property string pdeathWrapper: "if command -v setpriv >/dev/null; then exec setpriv --pdeathsig TERM -- \"$@\"; else exec \"$@\"; fi"

    function pdeath(argv) {
        return ["bash", "-c", root.pdeathWrapper, "--"].concat(argv)
    }

    function save(): void {
        stateFile.writeAdapter();
    }

    function rememberDevice(deviceId: string): void {
        const id = String(deviceId || "");
        root.activeDeviceId = id;
        if (id !== "") {
            const next = Array.from(root.recentDeviceIds || []).filter(value => value !== id);
            next.unshift(id);
            root.recentDeviceIds = next.slice(0, 5);
        }
        root.save();
    }

    function setFavoriteContact(contactId: string, favorite: bool): void {
        root.favoriteContactIds = root.updatedSet(root.favoriteContactIds, contactId, favorite);
        root.save();
    }

    function setFavoritePackage(packageName: string, favorite: bool): void {
        root.favoritePackages = root.updatedSet(root.favoritePackages, packageName, favorite);
        root.save();
    }

    function rememberPackage(packageName: string): void {
        const value = String(packageName || "");
        if (value === "") return;
        const next = Array.from(root.recentPackages || []).filter(item => item !== value);
        next.unshift(value);
        root.recentPackages = next.slice(0, 20);
        root.save();
    }

    function setNotificationCache(cache: var): void {
        root.notificationCache = cache && typeof cache === "object" ? cache : ({});
        root.save();
    }

    function updatedSet(values: var, value: string, present: bool): var {
        const clean = String(value || "");
        const next = Array.from(values || []).filter(item => item !== clean);
        if (present && clean !== "") next.push(clean);
        return next;
    }

    Process {
        id: ensureDir
        command: ["mkdir", "-p", root.stateDir]
        running: false
        onExited: if (!stateFile.text()) stateFile.writeAdapter()
    }

    FileView {
        id: stateFile
        path: root.stateDir + "/phone.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        JsonAdapter {
            id: state
            property string activeDeviceId: ""
            property var recentDeviceIds: []
            property var favoriteContactIds: []
            property var favoritePackages: []
            property var recentPackages: []
            property var notificationCache: ({})
        }
    }

    Component.onCompleted: ensureDir.running = true
}
