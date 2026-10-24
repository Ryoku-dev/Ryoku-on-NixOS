# keysounds

The shared parts of Ryoku's key-press sounds: the sample profiles, the importer
that makes one from any Mechvibes pack, and the standalone engine that plays a
sound on every key press for a compositor with no plugin system (niri).

A profile is a directory of short `.wav` / `.oga` / `.ogg` files named by role
(`down-*`, `up-*`, `space-*`, `enter-*`, `backspace-*`), one picked at random
per press so typing never sounds like a loop. Every shipped profile is a real
switch recording cut from the MIT-licensed
[Mechvibes](https://github.com/hainguyents13/mechvibes) packs; `profiles.txt`
maps each to its pack, and the licence ships beside the samples
(`ryoku-keysounds-profiles`).

Turning the feature on, its settings and adding a profile: [usage.md](usage.md).

Profiles are looked up under `$XDG_DATA_HOME/ryoku/keysounds` (yours) then
`/usr/share/ryoku/keysounds` (the package), so a profile of yours shadows a
shipped one of the same name.

## The engine (`main.rs`)

On Hyprland the feature is the `keysounds` compositor plugin
(`ryoku/hyprland/plugins/keysounds`), which sees every key the compositor sees.
niri has no plugin system, so this is a small daemon instead: it reads the
keyboard straight from evdev (the compositor hands it to libinput without
grabbing it, so reading the same device is the one way to hear every key in
every window) and plays each press through libcanberra, the freedesktop
event-sound library. The sound server caches each sample after its first play,
so a press costs one small request and overlapping presses mix there; nothing is
decoded or scheduled on the compositor's thread, which is why a burst of keys
never makes niri stutter.

It holds no compositor knowledge. The session starts it (a guarded line in the
compositor's autostart) and the window-manager provider writes its settings to a
neutral `key=value` file, `$XDG_STATE_HOME/ryoku/keysounds.conf`, which the
daemon re-reads within a second of a change. The keys `enabled`, `profile`,
`volume` (0..1) and `release` match the plugin's.

It has no third-party dependencies: `std` reads evdev and the config, and
libcanberra is reached through a direct FFI declaration, so it builds with a
single `rustc` call and no crate tree:

```
rustc -O --edition 2021 -C strip=symbols main.rs -o ryoku-keysounds
```

## Any Mechvibes pack

`ryoku-keysounds-import <pack-dir> [--name <profile>]` turns a pack from
[mechvibes.com](https://mechvibes.com) (a folder with `config.json`) into a
profile under `~/.local/share/ryoku/keysounds/`, slicing sprite packs and
copying per-key packs, release sounds included when the pack has them, every
sample normalised to one level. Needs `ffmpeg`.
