# rashin-app

`rashin-app` is the native host for the Rashin machine console. It provides a
single GTK3 window and renders the same Svelte interface that the
`ryoku-rashin` daemon serves to the loopback dashboard. The UI itself lives in
`ryoku/rashin/web`; this directory contains only the desktop host.

The host reads `port` from `$XDG_CONFIG_HOME/ryoku/rashin.json`, falling back
to port 3600, and opens `http://127.0.0.1:<port>/#/chat`. While the daemon is
unavailable it shows a black inline boot page and probes `/api/ping` every 500
milliseconds. A later failed page load returns to that boot page and resumes
probing.

`GtkApplication` owns the `dev.ryoku.rashin` application ID. Launching
`rashin-app` again presents the existing window instead of creating another.
The window size is stored in
`$XDG_STATE_HOME/ryoku/rashin-app.json`. Ctrl+R reloads the console and Ctrl+Q
closes it.

## Build

```sh
cmake -S ryoku/apps/rashin-app -B /tmp/rashin-app-build -G Ninja
cmake --build /tmp/rashin-app-build
```

The build requires CMake, Ninja, pkg-config, GTK3, and WebKit2GTK 4.1. The
result is `/tmp/rashin-app-build/rashin-app`.
