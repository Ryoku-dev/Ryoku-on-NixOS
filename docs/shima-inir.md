# Shima upstream runtime

This feature branch packages iNiR 2.33.0 at
`48cdcecb0f6089cfbb7019054602eab28e154b3b`. The source is a locked flake
input. The optional `ryoku-shima` package uses upstream's complete runtime
payload and dependency definition. It does not run the upstream installer
or import upstream's NixOS/Home Manager services.

## Development status

This is a working feature integration, not a completed parity release. Install or
update the optional runtime through RyoStore's Shima subshell listing
(`ryostore install barstyles iris`), then select Shima in Hub. No manual feature
flag or independently enabled service is required. Declarative provisioning is
also available with `programs.ryoku.shima.enable = true;`.

RyoStore builds a small standalone flake containing the compatibility layer and
the same locked iNiR source and **Ryoku-owned package set** (`ryokuPackagesNixpkgs`),
including the shared Quickshell screencopy compatibility patch. It must not use
Ryoku's separate `nixpkgs` compatibility input: that previously installed
Quickshell 0.3.2 / Qt 6.12 rather than the validated Quickshell 0.3.0 / Qt 6.11.1,
causing a reproducible Qt Quick startup crash. Its source is shipped with RyoStore;
the iNiR runtime and dependencies enter the user's dedicated Nix profile only
when installed. A successful build atomically advances that profile. Failed
builds preserve the installed generation. Updates use the same install action.
Removal releases only that profile's generations and returns an active selection
to Sumi, preserving Shima settings and newer user selections.

The existing Hub selection remains Shima, with the persistent identifier
`barStyle = "iris"`. Other styles keep their existing behavior.

## Ownership

Shima is a native Ryoku subshell, **not a replacement for Ryoku**. Ryoku Hub,
RyoStore, Ryogami and Ryoku's compositor, package and system controls remain
available. The Shima action catalogue includes a direct Ryoku Hub launcher.
The complete upstream iNiR desktop surfaces run under Ryoku's existing shell
selection and lifecycle management, with `iris` as the stable identifier.

Ryoku's Go daemon supervises the visual root. With the optional runtime installed
and Shima selected on Niri, it starts `ryoku-shima` instead of `qs -c shell`.
Only the active visual shell root changes. It stops and waits for the outgoing
root before starting another. There is no independent iNiR service, session
entry or autostart file.

Readiness is acknowledged by the selected family's critical and deferred root
loaders. Startup timeout or unexpected exit returns to the previous native style,
with QS Bar as the fresh-login fallback. A normal reload does not count as a crash.
Shell watcher children belong to the supervised process group. Applications
launched with Qt's detached API have their own session.

Ryoku retains compositor configuration, idle policy, app provisioning, keyring,
polkit, session security and Ryogami. Upstream's installer, conflict killer,
desktop autostart and automatic Niri preset activation are not called at startup.
Wallpaper selection, including per-output applies, is forwarded to Ryogami.
Shima subscribes to Ryogami's retained wallpaper frame, including external picker
and workspace changes. The native wallpaper painter exits with the old desktop
root. Shima preserves upstream rendering for stills and yields its painter while
a Ryogami external video player owns an output. Upstream's independent lock/PAM
implementation is replaced by Ryoku lock entry points. Upstream polkit dialog
visuals consume Ryoku's polkit topic and send responses over its local control
socket; no second authentication agent is registered.

## Settings

Shima configuration lives in `$XDG_CONFIG_HOME/ryoku/shima/config.json`.
The first launch copies the existing `shell.json.inir` subtree, without editing
the original, and defaults to iRiS. Later launches preserve the selected upstream
panel family and its own settings. State and cache are under their respective
XDG roots at `ryoku/shima`. Immutable or symlink-managed config is refused.

The global XDG configuration directory is not redirected, so applications
launched from Shima still find their normal user configuration.

## Widget and appearance migration

RyoStore exposes Shima as the existing `barstyles/iris` product. The full pinned
iNiR runtime, including its widget manager, iRiS widget faces, Cava visualizers,
frame pulse, Liquid Glass and other upstream themes, is installed through that
same entry. No second Shima product or independent widget pack is introduced.

The previous in-tree Shima widget implementation remains a fallback only while
the upstream runtime undergoes parity testing. Replace those legacy widgets
rather than offer two competing catalogues when the rollout is approved. The
existing install receipt and user settings must survive that transition.

iNiR's shared Cava service supplies the widget, player and frame visualizers.
Ryoku does not start a second competing audio visualizer. Audio-reactive motion
requires a working PipeWire monitor source and must be validated on hardware,
not inferred from static QML builds. iNiR's appearance and Liquid Glass presets
remain configured inside Shima; global compositor configuration and external
application theming stay owned by Ryoku.

## Ryoku desktop integration

The iRiS desktop surface stays available even if old `enabledPanels` lists
omit `irisBackground`. With Desktop Widgets enabled it hosts upstream widgets;
with them disabled the lightweight iRiS background keeps right-click actions.

The desktop menu offers Ryoku Hub, Subshells, Bar Studio and Desktop settings,
plus direct iRiS, Material ii and Waffle family switches.

Shima's appearance now has a separate Ryoku/Original iNiR selector. Ryoku mode
reads the real Ryoku wallpaper and named-theme palette using Ryoku's own Tokens
singleton and applies paper-and-ink styling to the upstream iRiS surfaces.
Unlike a theme preset, the frontend choice survives applying Liquid Glass or
any other iNiR theme. Full legacy Shima component-level visual parity is still
outstanding.

Frame Music now offers Wave, Frame or Both. Wave edges can be selected
individually, including both vertical sides. The Wave colours section exposes
the upstream Organic Edge palette source, movement, custom colours, and a
shortcut to its full colour picker. The Frame finish offers Pearl, Accent,
Highlight, Wallpaper and a custom hex colour.

Selecting the Ryoku card in the iRiS theme gallery enables the Ryoku frontend
without replacing the current iNiR theme. Liquid Glass remains selected and
can be changed independently. The appearance control persists in Shima's
schema, and the theme card visibly reflects whether the frontend is active.

The shared Cava subscriber reads
the chosen PipeWire monitor independently of MPRIS playback metadata.
The frame maps low, mid and high frequency energy to different edges rather
than making every side move with bass alone. Real audio and shader rendering
still need validation with active playback on physical monitors.

## Remaining parity work

- SDDM and login-screen themes are deferred to a later milestone. Shima does
  not replace Ryoku's greeter, lock screen or authentication ownership.
- Complete compositor preset/settings ownership and audit every optional
  integration and shortcut, including Ryoku-specific plugin/voice surfaces.
- Verify external theme/icon changes and restoration; automatic external theme
  application is disabled, so choosing Shima does not rewrite global theming.
- Exercise multi-monitor hotplug, suspend/resume, external video wallpaper,
  hardware controls, media and optional account-backed integrations on a test
  system. Nested tests isolate system D-Bus and audio and cannot verify hardware.

## Validation

The package exports the full upstream iRiS, Material ii and Waffle families.
Successful package construction or root readiness does not prove every panel's
functionality. RyoStore install/update and managed profiles have been exercised
in isolated XDG directories; all three families, settings windows, switching,
crash recovery and zero remaining Quickshell processes pass nested Niri probes.
A second nested probe runs a real isolated Ryogami daemon and renders its selected
wallpaper through the upstream shell. The polkit adapter passes a private fake
daemon test for prompts, secret transport, retries, echo mode and cancellation. Runtime probes use a nested Niri window, a private D-Bus session,
an isolated home and an isolated PID namespace. They never switch the live shell.

Focused checks:

```sh
python3 nix/tests/test-shima-runtime.py
python3 nix/tests/test-shima-appearance.py --runtime /nix/store/...-ryoku-shima-2.33.0
python3 nix/tests/test-shima-polkit.py --runtime /nix/store/...-ryoku-shima-2.33.0
cd ryoku/shell/ipc
go test -mod=vendor -run Shima ./...
go test -mod=vendor -race -run Shima ./...
```

Build the package, modified daemon and RyoStore install-source check from
the repository root:

```sh
nix build .#ryoku-shima .#ryoku-shell .#checks.x86_64-linux.ryoku-shima-store-universe
```

The isolated nested startup probe can optionally copy a Shima configuration into
its disposable home using `--config-file` and run a short crash check with
`--startup-only`. The real-config startup, three-panel navigation, settings,
subshell switching and crash fallback checks pass using the corrected
RyoStore-built package. Live hardware validation remains outstanding.

Compatibility changes live in `nix/packages/shima`. Patch anchors fail the build
when upstream changes. Upstream source and notices remain separate from those
changes, so the pin can be reviewed and updated without another vendored tree.

## Verified in this branch

- The optional runtime and modified Go daemon build through Nix.
- The package layout check retains all three families and the upstream license,
  and does not expose the independent upstream lifecycle command.
- Shima settings tests cover first launch, subsequent launch, copying the legacy
  namespace, and preserving managed config symlinks.
- Go lifecycle tests cover installed runtime selection, Niri gating, private readiness, timeout,
  selection changes, fallback, family persistence, stale exits and scoped cleanup.
  The focused suite passes with the race detector. Go vet passes.
- All 14 Hub navigation/gallery tests pass, including optional Shima install state.
- The complete RyoStore test suite and four Python settings tests pass.
- Flake evaluation (`nix flake check --no-build`) passes. Targeted layout,
  bar-style source-integrity, notification-ownership and installer-option checks
  build successfully. This is not a full build of every flake check.
- The nested compositor test visibly renders iRiS, Material ii and Waffle.
  It verifies family persistence through the actual modified daemon, opens the
  upstream settings surface, switches back to Python, re-enters Shima, kills its
  root, observes fallback to Python, and finds zero Quickshell processes after
  the daemon shuts down. Each family answers the notification D-Bus API and
  reports an active tray host on the private session bus.
- Nix evaluation confirms Shima is absent from default system packages and present
  only when its option is enabled, or installed into its RyoStore-owned user
  profile. RyoStore itself closes over the installer source without the runtime.
  Existing dependency pins are unchanged.

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
