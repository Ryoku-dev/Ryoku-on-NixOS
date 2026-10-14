#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source = root / "ryoku/shell/quickshell/shell/modules/launcher/variants/main/Launcher.qml"
text = source.read_text()
selection = text[text.index('    property string primaryDbus:'):text.index('    readonly property bool hasMedia:')]
selection = selection.replace('Players.realPlayers()', 'root.players').replace('void Mpris.players.values;', '')

test = '''import QtQuick
import QtTest

TestCase {
    name: "LauncherPlayerBinding"
    Component {
        id: subject
        Item {
            id: root
            property var players: []
SELECTION
        }
    }
    Component {
        id: player
        QtObject {
            property string dbusName: ""
            property bool isPlaying: false
            property bool canControl: true
            property string trackTitle: "Track"
        }
    }
    function init() {
        failOnWarning(/.*[Bb]inding loop.*/)
    }
    function test_selection() {
        var a = createTemporaryObject(player, this, {dbusName: "a"})
        var b = createTemporaryObject(player, this, {dbusName: "b"})
        var view = createTemporaryObject(subject, this)
        compare(view.activePlayer, null)
        view.players = [a, b]
        compare(view.activePlayer, a)
        tryCompare(view, "primaryDbus", "a")
        b.isPlaying = true
        compare(view.activePlayer, b)
        tryCompare(view, "primaryDbus", "b")
        b.isPlaying = false
        compare(view.activePlayer, b)
        a.isPlaying = true
        compare(view.activePlayer, a)
        tryCompare(view, "primaryDbus", "a")
        a.isPlaying = false
        compare(view.activePlayer, a)
        view.players = [b]
        compare(view.activePlayer, b)
        tryCompare(view, "primaryDbus", "b")
        view.players = []
        compare(view.activePlayer, null)
    }
    function test_rapid_switch() {
        var a = createTemporaryObject(player, this, {dbusName: "a"})
        var b = createTemporaryObject(player, this, {dbusName: "b"})
        var view = createTemporaryObject(subject, this, {players: [a, b]})
        b.isPlaying = true
        a.isPlaying = true
        compare(view.activePlayer, a)
        tryCompare(view, "primaryDbus", "a")
        a.isPlaying = false
        tryCompare(view, "primaryDbus", "b")
        b.isPlaying = false
        compare(view.activePlayer, b)
    }
}
'''.replace('SELECTION', selection)

with tempfile.TemporaryDirectory(prefix="ryoku-player-test-") as directory:
    Path(directory, "tst_players.qml").write_text(test)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen")
    raise SystemExit(subprocess.call(["qmltestrunner", "-input", directory], env=env))
