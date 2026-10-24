pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import inir.modules.common
import inir.modules.common.functions

/**
 * The emoji catalogue behind the palette's `:` mode: the vendored emoji data
 * file, fuzzy-searchable by name.
 */
Singleton {
    id: root
    property string emojiDataPath: `${Directories.scriptsPath}/emoji/emoji-data.txt`

    property list<var> list

    property bool sloppySearch: Config.options?.search?.sloppy ?? false
    property real scoreThreshold: 0.2

    readonly property var preparedEntries: list.map(a => ({
        name: Fuzzy.prepare(`${a}`),
        entry: a
    }))

    function fuzzyQuery(search: string): var {
        if (root.sloppySearch) {
            const results = root.list.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, preparedEntries, {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        })
    }

    FileView {
        id: emojiFileView
        path: Qt.resolvedUrl(root.emojiDataPath)
        onLoadedChanged: root.list = emojiFileView.text()
            .split("\n").filter(line => line.trim() !== "").map(line => line.trim())
    }
}
