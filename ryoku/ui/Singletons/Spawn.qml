pragma Singleton

import Quickshell

// Start a child process without handing it Quickshell's crash-recovery handle.
//
// A Quickshell instance that has crashed once carries __QUICKSHELL_CRASH_INFO_FD
// in its environment, naming an inherited memfd that records the config it came
// back from. Upstream reads that variable before it parses any argument
// (checkCrashRelaunch, src/launch/main.cpp), so `qs -c ryowalls` started from the
// desktop ignored `-c ryowalls` and relaunched the desktop instead: opening an app
// from the launcher drew a second bar and a second dock over the first, and the
// frame rate paid for both. The memfd is dup'd without CLOEXEC upstream, so the
// variable is the only half we can take away, and taking it away is enough.
//
// Everything that can end up running Quickshell goes through here: an app, a
// desktop entry, a terminal, a `qs` call, or a shell line that runs one.
Singleton {
    id: spawn

    // A null value unsets the variable for the child rather than setting it
    // empty. Process.environment takes the same map.
    readonly property var env: ({
            "__QUICKSHELL_CRASH_INFO_FD": null,
            "__QUICKSHELL_CRASH_DUMP_PID": null,
            "__QUICKSHELL_CRASH_DUMP_FD": null,
            "__QUICKSHELL_CRASH_LOG_FD": null,
            "__QUICKSHELL_CRASH_SIGNAL": null
        })

    // NixOS exposes generation-owned systemd-run here. User applications go
    // into independent app.slice scopes so ryoku-shell.service can retain
    // KillMode=control-group without taking normal desktop apps down with it.
    readonly property string systemdRun:
        Quickshell.env("RYOKU_SYSTEMD_RUN") || ""

    function appCommand(command) {
        if (!command || command.length === 0)
            return [];

        if (spawn.systemdRun === "")
            return command;

        const argv = [
            spawn.systemdRun,
            "--user",
            "--scope",
            "--collect",
            "--quiet",
            "--slice=app.slice",
            "--"
        ];

        for (let i = 0; i < command.length; i++)
            argv.push(String(command[i]));

        return argv;
    }

    // run(argv) launches and forgets, like Quickshell.execDetached. The optional
    // working directory is a desktop entry's Path=; empty keeps our own.
    function run(command, workingDirectory) {
        if (!command || command.length === 0)
            return;
        const ctx = {
            "command": command,
            "environment": spawn.env
        };
        if (workingDirectory)
            ctx.workingDirectory = String(workingDirectory);
        Quickshell.execDetached(ctx);
    }

    // runApp() is specifically for user-facing applications. Shell-owned
    // helpers, capture processes and Ryoku surfaces must continue using run().
    function runApp(command, workingDirectory) {
        if (!command || command.length === 0)
            return;

        spawn.run(
            spawn.appCommand(command),
            workingDirectory || ""
        );
    }
}
