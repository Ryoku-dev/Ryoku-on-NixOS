pragma Singleton

import Quickshell

// Detached children must not inherit Quickshell's crash-recovery handles.
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

<<<<<<< port (unstable-dev)
    // runApp() is specifically for user-facing applications. Shell-owned
    // helpers, capture processes and Ryoku surfaces must continue using run().
    function runApp(command, workingDirectory) {
        if (!command || command.length === 0)
            return;

        spawn.run(
            spawn.appCommand(command),
            workingDirectory || ""
        );
=======
    function runApp(argv, opts) {
        if (!argv || argv.length === 0)
            return;
        const options = opts || {};
        const command = ["ryoku-host", "app"];
        if (options.cwd)
            command.push("--cwd", String(options.cwd));
        if (options.label)
            command.push("--label", String(options.label));
        command.push("--");
        for (let i = 0; i < argv.length; i++)
            command.push(String(argv[i]));
        spawn.run(command);
>>>>>>> upstream Ryoku 1.3.6 (7a51ec1)
    }
}
