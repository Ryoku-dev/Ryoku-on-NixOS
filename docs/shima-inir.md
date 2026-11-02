# Shima upstream runtime

This feature branch packages iNiR 2.33.0 at
`48cdcecb0f6089cfbb7019054602eab28e154b3b`. The source is a locked flake
input. The optional `ryoku-shima` package uses upstream's complete runtime
payload and dependency definition. It does not run the upstream installer
or import upstream's NixOS/Home Manager services.

## Development status

This is an experimental integration, not a completed parity release. The normal
built-in `iris` scene remains the default implementation. The replacement runtime
requires an explicit `programs.ryoku.shima.enable = true;` in a test system.
Do not enable it in a daily session until the remaining host bridges are finished.

The existing Hub selection remains Shima, with the persistent identifier
`barStyle = "iris"`. Other styles keep their existing behavior.

## Ownership

Ryoku's Go daemon supervises the visual root. With the experimental option enabled
and Shima selected on Niri, it starts `ryoku-shima` instead of `qs -c shell`.
It stops and waits for the outgoing root before starting another. There is no
independent iNiR service, session entry or autostart file.

Readiness is acknowledged by the selected family's critical and deferred root
loaders. Startup timeout or unexpected exit returns to the previous native style,
with QS Bar as the fresh-login fallback. A normal reload does not count as a crash.
Shell watcher children belong to the supervised process group. Applications
launched with Qt's detached API have their own session.

Ryoku retains compositor configuration, idle policy, app provisioning, keyring,
polkit, session security and Ryogami. Upstream's installer, conflict killer,
desktop autostart and automatic Niri preset activation are not called at startup.
Wallpaper selection is forwarded to Ryogami. Host ownership bridges are not yet
complete for every upstream wallpaper mode.

## Settings

Shima configuration lives in `$XDG_CONFIG_HOME/ryoku/shima/config.json`.
The first launch copies the existing `shell.json.inir` subtree, without editing
the original, and defaults to iRiS. Later launches preserve the selected upstream
panel family and its own settings. State and cache are under their respective
XDG roots at `ryoku/shima`. Immutable or symlink-managed config is refused.

The global XDG configuration directory is not redirected, so applications
launched from Shima still find their normal user configuration.

## Remaining integration work

- Complete Ryogami's per-output, preview and transition bridge while preserving
  upstream wallpaper widgets and avoiding a second wallpaper renderer.
- Bridge upstream lock and polkit visuals to Ryoku's proven session-security
  protocol. Existing Ryoku lock handling remains authoritative.
- Complete theme/icon restoration, compositor presets and every Ryoku shortcut.
- Validate notification/tray ownership with the resident Ryoku daemon.
- Publish through RyoStore's existing subshell installation workflow. No Store
  listing should claim complete parity before these checks pass.
- Exercise multi-monitor hotplug, suspend/resume, session recovery, hardware
  controls, media and optional account-backed integrations on a test system.

## Validation

The package exports the full upstream iRiS, Material ii and Waffle families.
Successful package construction or root readiness does not prove every panel's
functionality. Runtime probes use a nested Niri window, a private D-Bus session,
an isolated home and an isolated PID namespace. They never switch the live shell.

Focused checks:

```sh
python3 nix/tests/test-shima-runtime.py
cd ryoku/shell/ipc
go test -mod=vendor -run Shima ./...
go test -mod=vendor -race -run Shima ./...
```

Build the package and the modified daemon from the repository root:

```sh
nix build .#ryoku-shima .#ryoku-shell
```

Compatibility changes live in `nix/packages/shima`. Patch anchors fail the build
when upstream changes. Upstream source and notices remain separate from those
changes, so the pin can be reviewed and updated without another vendored tree.

## Verified in this branch

- The optional runtime and modified Go daemon build through Nix.
- The package layout check retains all three families and the upstream license,
  and does not expose the independent upstream lifecycle command.
- Shima settings tests cover first launch, subsequent launch, copying the legacy
  namespace, and preserving managed config symlinks.
- Go lifecycle tests cover opt-in, Niri gating, private readiness, timeout,
  selection changes, fallback, family persistence, stale exits and scoped cleanup.
  The focused suite passes with the race detector. Go vet passes.
- The Hub Subshells navigation regression tests pass with the existing iris ID.
- The nested compositor test visibly renders iRiS, Material ii and Waffle.
  It verifies family persistence through the actual modified daemon, opens the
  upstream settings surface, switches back to Python, re-enters Shima, kills its
  root, observes fallback to Python, and finds zero Quickshell processes after
  the daemon shuts down.
- Nix evaluation confirms Shima is absent from default system packages and present
  only when its option is enabled. Existing dependency pins are unchanged.

The full Go suite has the same seven reported lock-test failures on both the
unmodified baseline and this branch. These include FHS assumptions such as
/usr/bin/bash. The complete suite is therefore not reported as green.

These probes run with an isolated home, configuration, runtime directory, PID
namespace and D-Bus session. The system bus is unavailable deliberately, so audio,
Bluetooth, power management and authentication behavior are not verified by this
test. The live desktop, active system generation and original dirty checkout were
not changed.

Run the nested probe explicitly from a Wayland session after building the packages:

```sh
python3 nix/tests/test-shima-nested.py   --runtime /nix/store/PATH-ryoku-shima-2.33.0   --daemon /nix/store/PATH-ryoku-shell-unstable   --native-root /run/current-system/sw/share/ryoku/config   --bwrap /path/to/bwrap   --output /path/to/probe-output
```

The placeholder paths above must be replaced with the package output paths.
The test opens a nested Niri window. It does not replace the active desktop.
