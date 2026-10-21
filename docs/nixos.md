# Ryoku on NixOS

Ryoku on NixOS is the NixOS implementation of the Ryoku desktop.

The desktop experience is shared with Ryoku on Arch: Hyprland, niri or MangoWM, the
Ryoku shell, Hub, Ryostore, theming, launcher, lockscreen, media surfaces and
the wider Ryoku UI all remain Ryoku. The difference is how the operating system
underneath is managed.

On NixOS, Ryoku uses Nix packages, NixOS modules and normal NixOS generations
instead of Pacman, the AUR, mkinitcpio or an Arch-specific boot stack.

## Requirements

Ryoku on NixOS currently targets:

- `x86_64-linux`
- an existing flake-based NixOS installation
- Hyprland, niri or MangoWM on Wayland
- a reasonably recent NixOS package set

The installer integrates Ryoku into the system you already have. It does **not**
repartition disks, replace the bootloader, choose a kernel, or take ownership of
the host's graphics-driver configuration.

## Recommended installation

Run the installer as your normal user:

```bash
nix run github:Ryoku-dev/Ryoku-on-NixOS/main#install
```

The installer requests elevated privileges only when it needs to write system
configuration or build/switch the NixOS generation.

For a preview first:

```bash
nix run github:Ryoku-dev/Ryoku-on-NixOS/main#install -- \
```

A dry run prints the proposed `flake.nix` changes and generated `ryoku.nix`
without modifying the system.

### Custom flake path or host

The installer defaults to `/etc/nixos` and automatically selects the current
host when it can.

For another flake location or a multi-host configuration:

```bash
nix run github:Ryoku-dev/Ryoku-on-NixOS/main#install -- \
  --flake /path/to/nixos#hostname
```

Useful installer options:

```text
--flake PATH[#HOST]   NixOS flake to configure
--source REF          Ryoku flake reference
--compositor NAME     Initial compositor: hyprland, niri, or mango
--browser NAME        Browser: chromium or firefox
--dry-run             Show proposed changes without writing them
-y, --yes             Skip confirmation
-h, --help            Show help
```

## What the installer changes

The installer adds Ryoku as a flake input, imports the Ryoku NixOS module, and
creates an installer-managed `ryoku.nix` containing:

```nix
{ ... }:

{
  programs.ryoku = {
    enable = true;
    defaultCompositor = "hyprland";
    browser = "chromium";
  };
}
```

Before changing the live configuration it stores backups under:

```text
/var/backups/ryoku-nixos/
```

It then:

1. updates the flake lock,
2. builds the new NixOS generation,
3. switches only after the build succeeds,
4. materializes the user-facing Ryoku configuration.

If locking, building, or switching fails, the installer restores the backed-up
configuration files.

## Manual flake integration

The installer is the recommended route, but Ryoku can also be added manually.

Add the NixOS port as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ryoku = {
      url = "github:Ryoku-dev/Ryoku-on-NixOS";
    };
  };
}
```

Ryoku keeps its own runtime package set pinned independently from the host.
Do not override that package pin: host `nixpkgs` updates must not change
Ryoku's fixed-output dependency derivations.

Then import the module in the target NixOS configuration:

```nix
{
  outputs = { nixpkgs, ryoku, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      modules = [
        ryoku.nixosModules.default

        {
          programs.ryoku.enable = true;
        }
      ];
    };
  };
}
```

Replace `my-host` with the host name used by your own flake.

Build and switch normally:

```bash
sudo nixos-rebuild switch --flake .#my-host
```

For a manual integration, the packaged materializer is also exposed as:

```bash
nix run github:Ryoku-dev/Ryoku-on-NixOS/main#ryoku-materialize
```

Normal installer-managed systems run materialization automatically after a
successful switch.

## What the NixOS module owns

The NixOS module provides the machine-facing integration needed by the Ryoku
desktop, including:

- Ryoku packages and runtime dependencies
- the Ryoku Hyprland, niri and MangoWM provider/session package sets
- PipeWire and WirePlumber integration
- NetworkManager and Bluetooth integration
- polkit and keyring support
- power and hardware-information helpers
- required fonts and desktop assets
- Ryoku user services
- NixOS-native system bridges
- user configuration materialization

Ryoku-owned services are expressed declaratively rather than copied into a
user-local systemd tree.

Both compositor sessions and their Ryoku providers come from Ryoku's locked
package set. ABI-sensitive Hyprland plugins therefore remain compatible with
the Hyprland build in the same generation.

At the display manager, choose **Hyprland**, **niri** or **MangoWM**. All three
sessions use the same Ryoku shell and neutral desktop settings. The installer's
`defaultCompositor` choice only preselects the initial session; every provider
remains deployed, so Hub switching never needs a mutable package transaction.

`browser` is similarly declarative. The installer can choose Chromium or
Firefox, and the selected package becomes Ryoku's fallback browser role while a
Hub Default Apps override still wins. Other optional applications remain owned
by the host NixOS configuration rather than a second mutable provisioning ledger.

## Materialized user configuration

NixOS owns the packaged source of truth, while Ryoku materializes the
user-facing configuration that the desktop expects at runtime.

Initial user data that needs preserving is backed up under:

```text
~/.local/state/ryoku/nix/backups/
```

The original backup location is recorded in:

```text
~/.local/state/ryoku/nix/initial-backup-path
```

User-owned overrides remain separate from the packaged base so normal updates do
not require editing files in the Nix store.

## Session environment

The NixOS deployment imports the active compositor environment into the
systemd user manager.

Values such as:

```text
WAYLAND_DISPLAY
HYPRLAND_INSTANCE_SIGNATURE
NIRI_SOCKET
```

come from the live compositor session.

Do not add a second manual Ryoku shell `exec-once` when the NixOS module already
manages `ryoku-shell.service`.

## Updating

Use the normal Ryoku command:

```bash
ryoku update
```

On NixOS, this uses Ryoku's Nix-specific update backend. It advances the
configured Ryoku flake input, builds the resulting NixOS generation, and then
switches to it.

It does **not** run Pacman or the AUR.

Systems using a local `path:` Ryoku input are intentionally not mutated by the
updater. Update the checkout yourself and rebuild the host flake normally.

Because updates produce ordinary NixOS generations, standard NixOS rollback
mechanisms remain available.

### Urgent updates

A fix every box should take right away (a lock screen that opens without a
password, an update that breaks the session) is marked with a trailer in its
commit message, beside `Note:`:

```text
Urgent: the lock screen could be skipped after waking from sleep
```

The reason is the alert's text: one plain sentence, 160 characters at most.
The commit-msg hook checks that it sits in the last paragraph and that a
commit carries one at most.

Only a maintainer of this repository marks a commit urgent, in their own
commit on `unstable-dev` or `main`, or in the merge commit of a pull request.
A box reads the trailer only on its branch's first-parent line, so a
contributor's commit, which arrives as the second parent of its merge, never
alerts anyone, and the **Urgent trailer** workflow fails a pull request whose
commits carry one. Upstream Ryoku commits never alert: when a sync brings a
fix that cannot wait, the sync's merge commit carries the trailer.

A box sees an urgent commit once the branch its Ryoku flake input follows
carries it and the box does not run it yet. `ryoku-nix-update status` names
the input's GitHub repository, the commit in `flake.lock` and the branch tip;
`ryoku status` reads the trailers between the two through GitHub's compare
API and caches the answer until either commit moves. A local `path:` checkout
with a GitHub `origin` compares its `HEAD` with the tip of its branch there;
any other input sees nothing.

`ryoku status --json` lists them under `urgent`, newest first, and
`ryoku status --urgent` prints that list alone. The shell daemon asks
`ryoku status --urgent` every hour between its full checks and runs a full
check when an urgent commit appears. The shell then raises a critical
notification that stays up, comes through Do Not Disturb and offers
**Update now** (`ryoku update --gui`, with the Hub on its Updates page) and
**Later**. Closing it snoozes it for six hours; it comes back at the next
login and goes away once the update lands. The Hub's Updates page marks the
update URGENT with each reason.

`urgentUpdates.enabled` in `shell.json` (Hub > Updates, **Urgent alerts**)
turns the alert and the hourly probe off, and automatic checks set to off
stop the probe too. A rice never carries the switch. Nothing is sent
anywhere: the probe reads the public branch tip and GitHub's public compare
API with no identifier. Offline or rate-limited, it shows nothing new and
tries again an hour later.

## Package reporting

The Hub reports NixOS packages as:

```text
SYSTEM · USER · TOTAL
```

`SYSTEM` is based on direct packages declared for the system.

`USER` represents packages installed through the user's imperative Nix profile.

The complete Nix store closure is intentionally not shown because it contains
transitive dependencies that the user did not directly select.

## Ryostore

Most Ryostore content is desktop-level content and is shared between the Arch and
NixOS implementations: themes, bar styles, shell components, Fastfetch presets,
lockscreen content and similar products do not need separate catalogues.

App/package bundles are the main exception because package installation is
platform-specific. Those need Nix-native definitions before they can provide the
same experience on NixOS.

Ryoku therefore keeps one shared Ryostore catalogue rather than maintaining a
separate NixOS store.

## Arch and NixOS

The goal is **desktop parity, not package-manager parity**.

The same Ryoku desktop can sit on top of two different system-management models:

| Ryoku on Arch | Ryoku on NixOS |
| --- | --- |
| Pacman / AUR | Nix / NixOS modules |
| Arch package transactions | NixOS generations |
| Arch service/package integration | Declarative NixOS integration |
| Arch boot/initramfs tooling | Host NixOS boot policy |
| Snapshot/update flow from Arch | Standard NixOS rollback generations |

The UI and desktop product remain Ryoku; the operating-system integration follows
the conventions of the host platform.

## Development

From a local checkout:

```bash
nix develop
```

Run the development environment with:

```bash
nix run .#ryoku-dev
```

Useful flake outputs include:

```text
.#install
.#ryoku-dev
.#ryoku-materialize
```

The flake also exposes the individual Ryoku packages and checks used to build and
validate the NixOS port.

## Related documentation

- [`README.md`](../README.md): project overview and installation entry point
- [`structure.md`](structure.md): repository layout
- [`development.md`](development.md): development conventions
- [`store.md`](store.md): Ryostore architecture
- [`plugins.md`](plugins.md): plugin system
- [`barstyles.md`](barstyles.md): bar-style architecture
