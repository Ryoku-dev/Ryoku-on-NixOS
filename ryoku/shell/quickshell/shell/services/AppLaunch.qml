pragma Singleton

import Quickshell
import Ryoku.Ui.Singletons

// One launcher for XDG desktop entries. Quickshell parses Terminal=true into
// runInTerminal but spawns no terminal for it, so a TUI (btop, yazi, nvim) got no
// tty and died at once; ryoku-app owns which terminal the user picked.
//
// Launching goes through Spawn rather than DesktopEntry.execute(): execute()
// hands the child the desktop's whole environment, and a Quickshell app that
// inherits the crash handle in it relaunches the desktop instead of starting.
Singleton {
    id: root

    // run(entry) launches the entry; run(entry, action) launches one of its
    // actions, which inherit Terminal= from the entry that declares them.
    function run(entry, action) {
        const target = action || entry;
        if (!target)
            return;
<<<<<<< port (main)
        const argv = entry && entry.runInTerminal ? (target.command || []) : [];
        if (argv.length === 0) {
            Spawn.runApp(target.command, entry ? entry.workingDirectory : "");
            return;
        }
        const command = ["ryoku-app", "terminal", "--"];
        for (let i = 0; i < argv.length; i++)
            command.push(String(argv[i]));
        Spawn.runApp(command);
=======
        const argv = Array.from(target.command || []).map(arg => String(arg));
        if (argv.length === 0)
            return;
        const command = entry && entry.runInTerminal
            ? ["ryoku-app", "terminal", "--"].concat(argv)
            : argv;
        Spawn.runApp(command, {
            cwd: entry ? entry.workingDirectory : "",
            label: entry ? entry.id : ""
        });
>>>>>>> upstream Ryoku 1.0.4 (ad2d365)
    }
}
