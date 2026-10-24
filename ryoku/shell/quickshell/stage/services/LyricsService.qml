pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import inir.services as InirServices

Singleton {
    id: root

    property bool isInitialized: false
    readonly property var syncedLines: InirServices.LyricsService.lyricsLines ?? []
    readonly property int currentIndex: InirServices.LyricsService.activeIndex
    readonly property bool hasSyncedLines: root.syncedLines.length > 0
    readonly property string statusText: root.currentIndex >= 0 && root.currentIndex < root.syncedLines.length
        ? String(root.syncedLines[root.currentIndex].text ?? "") : ""
    readonly property string status: InirServices.LyricsService.status
    readonly property bool searching: root.status === "loading"
    readonly property bool hasAnyLyrics: root.hasSyncedLines

    function initiliazeLyrics(): void {
        if (root.isInitialized)
            return;
        root.isInitialized = true;
        InirServices.LyricsService.subscribe();
    }

    function initializeLyrics(): void { root.initiliazeLyrics(); }

    function getLineDuration(index): real {
        if (index < 0 || index >= root.syncedLines.length)
            return 0;
        if (index === root.syncedLines.length - 1)
            return 5;
        return Math.max(0, Number(root.syncedLines[index + 1].time ?? 0)
            - Number(root.syncedLines[index].time ?? 0));
    }

    function changeDurationToIndex(index): void {
        if (index < 0 || index >= root.syncedLines.length)
            return;
        const player = InirServices.MprisController.activePlayer;
        if (player)
            player.position = Number(root.syncedLines[index].time ?? 0);
    }

    Component.onDestruction: {
        if (root.isInitialized)
            InirServices.LyricsService.unsubscribe();
    }
}
