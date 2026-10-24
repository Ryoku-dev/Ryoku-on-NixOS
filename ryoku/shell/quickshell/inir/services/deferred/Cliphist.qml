pragma Singleton
pragma ComponentBehavior: Bound

import inir.modules.common
import inir.modules.common.functions
import QtQuick
import Quickshell
import inir.services
import shell.services as RyokuServices

Singleton {
    id: root

    property int maxEntries: 400
    property bool sloppySearch: Config.options?.search?.sloppy ?? false
    property real scoreThreshold: 0.2

    readonly property var entries: Array.from(RyokuServices.Clipboard.entries ?? []).slice(0, root.maxEntries)
    readonly property var pinned: Array.from(Config.options?.clipboard?.pinned ?? [])
    readonly property var missingPinnedEntries: root.pinned.filter(text => {
        return !root.entries.some(entry => root.isCompleteText(entry) && String(entry.preview ?? "") === String(text))
    }).map(text => ({
        id: "",
        kind: "text",
        mime: "text/plain",
        size: root.utf8Size(String(text)),
        preview: String(text),
        thumb: "",
        thumbW: 0,
        thumbH: 0,
        pinnedOnly: true
    }))
    readonly property var searchEntries: root.missingPinnedEntries.concat(root.entries)
    readonly property var preparedEntries: root.searchEntries
        .filter(entry => entry.kind === "text")
        .map(entry => ({
            name: Fuzzy.prepare(String(entry.preview ?? "")),
            entry: entry
        }))

    function fuzzyQuery(search: string): var {
        if (search.trim() === "")
            return root.searchEntries.slice(0, root.maxEntries + root.missingPinnedEntries.length)

        const candidates = root.searchEntries.filter(entry => entry.kind === "text")
        if (root.sloppySearch) {
            return candidates.slice(0, Math.min(100, candidates.length)).map(entry => ({
                entry: entry,
                score: Levendist.computeTextMatchScore(
                    String(entry.preview ?? "").toLowerCase(),
                    search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
                .map(item => item.entry)
        }

        return Fuzzy.go(search, root.preparedEntries, {
            all: true,
            key: "name"
        }).map(result => result.obj.entry)
    }

    function entryIsImage(entry): bool {
        return entry?.kind === "image"
    }

    function copy(entry): void {
        if (!entry)
            return
        if (entry.pinnedOnly === true) {
            Quickshell.clipboardText = String(entry.preview ?? "")
            return
        }
        RyokuServices.Clipboard.copy(Number(entry.id))
    }

    function deleteEntry(entry): void {
        if (!entry)
            return
        if (entry.pinnedOnly === true) {
            root.unpin(String(entry.preview ?? ""))
            return
        }
        RyokuServices.Clipboard.del(Number(entry.id))
    }

    function wipe(): void {
        RyokuServices.Clipboard.clear()
    }

    function utf8Size(text): int {
        const value = String(text ?? "")
        let size = 0
        for (let i = 0; i < value.length; i++) {
            const code = value.charCodeAt(i)
            if (code <= 0x7f) {
                size += 1
            } else if (code <= 0x7ff) {
                size += 2
            } else if (code >= 0xd800 && code <= 0xdbff
                    && i + 1 < value.length
                    && value.charCodeAt(i + 1) >= 0xdc00
                    && value.charCodeAt(i + 1) <= 0xdfff) {
                size += 4
                i++
            } else {
                size += 3
            }
        }
        return size
    }

    // A preview is the full text only when its UTF-8 byte count still equals
    // the daemon's captured size. This also admits exact 200-character entries.
    function isCompleteText(entry): bool {
        return entry?.kind === "text"
            && root.utf8Size(String(entry.preview ?? "")) === Number(entry.size ?? -1)
    }

    function isPinnable(entry): bool {
        return root.isCompleteText(entry) && String(entry.preview ?? "").length > 0
    }

    function pinPreview(text): string {
        const firstLine = String(text ?? "").split("\n").find(line => line.trim().length > 0) ?? ""
        return firstLine.trim()
    }

    function isPinned(text): bool {
        return root.pinned.indexOf(text) !== -1
    }

    function pinnedTextFor(entry): string {
        if (!entry)
            return ""
        const text = String(entry.preview ?? "")
        if (entry.pinnedOnly === true)
            return root.isPinned(text) ? text : ""
        return root.isCompleteText(entry) && root.isPinned(text) ? text : ""
    }

    function unpin(text): void {
        Config.setNestedValue("clipboard.pinned", root.pinned.filter(pin => pin !== text))
    }

    function pinEntry(entry): void {
        if (!root.isPinnable(entry))
            return
        const text = String(entry.preview ?? "")
        if (!root.isPinned(text))
            Config.setNestedValue("clipboard.pinned", [text, ...root.pinned])
    }
}
