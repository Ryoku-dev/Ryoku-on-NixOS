# Ryoku on NixOS ISO

The Ryoku ISO is a bootable NixOS installer image that carries the exact Ryoku
source revision used to build it and launches `ryoku-install --iso` on the first
local TTY1 login.

## Live environment

The live image provides:

- current Nix with flakes enabled;
- NetworkManager and SSH for recovery/testing;
- the guided Ryoku terminal installer;
- the exact Ryoku source tree embedded at `/etc/ryoku/source`;
- the standard NixOS installation/recovery toolbox.

Closing the installer returns to the live shell. Run `ryoku-install --iso` to
open it again.

## Guided installation

The ISO uses one continuous Bubble Tea wizard for the complete whole-disk flow.
The backend receives a fully validated non-interactive install plan; it does not
fall back to shell prompts halfway through the installation. The wizard covers:

- HTTPS connectivity to `cache.nixos.org`, with NetworkManager `nmtui` recovery;
- target disk and ext4/Btrfs filesystem;
- hostname, username and a masked/confirmed password;
- timezone, locale and keyboard layout;
- kernel policy: NixOS default, latest, or Zen from the pinned nixpkgs;
- Ryoku compositor: Hyprland, niri, or MangoWM;
- browser, shell and optional Ryoku apps/tools;
- generated Ryoku configuration, or advanced input-only import of an existing
  NixOS flake;
- final review and exact target-disk confirmation.

GPU vendors and UEFI/BIOS mode are still detected by the backend. Password
plaintext never enters backend argv, a temporary file, or installer logs: the
TUI sends only its yescrypt hash through the backend environment.

Before partitioning, the user must type the exact target disk path. The backend
validates the same path again before `wipefs`. Unattended installs require both
`--disk` and a matching `--confirm-disk`. The installer refuses the disk backing
the live medium and writable targets smaller than 16 GiB. The live image also
enables compressed zram and automatically limits Nix build parallelism on
lower-memory machines; 8 GiB RAM is the tested minimum for the default full
desktop installation.

### Import existing NixOS flake

Import mode is deliberately conservative. It copies the selected flake into the
new system, adds only the `ryoku` flake input, and leaves the imported modules,
users, packages, desktop policy and nixpkgs input under the user's ownership.
The source directory is never edited in place.

For disk safety, the imported tree must contain a root
`hardware-configuration.nix`; the installer replaces that file with hardware
configuration generated for the new machine. Filesystem/disk declarations
outside that file are rejected instead of guessing whether old UUIDs are safe.
If the flake exposes more than one `nixosConfiguration`, the host must be chosen
explicitly.

**Guided dual boot / preserve-existing-partitions is not implemented yet.** The
selected installation disk is erased. Advanced users can leave the installer
and use the normal NixOS live shell for manual partitioning.

## Installed `/etc/nixos`

The canonical installed config comes from [`../iso-configs`](../iso-configs):

```text
/etc/nixos/
├── flake.nix
├── configuration.nix
├── hardware-configuration.nix
├── install-values.nix
├── pkgs.nix
├── ryoku.nix
├── hardware/
│   └── gpu/
│       ├── common.nix
│       ├── nvidia.nix
│       ├── amd.nix
│       └── intel.nix
└── modules/
    └── module-example.nix
```

Only `install-values.nix` and `hardware-configuration.nix` are machine-specific.
The other files stay clean and user-editable. Release ISOs keep the normal
`main` / `nixos-unstable` input URLs while the generated `flake.lock` pins both
Ryoku and Nixpkgs to the exact revisions tested by the image. A later
`nix flake update` therefore advances normally.

Rebuild an installed system with:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#ryoku
```

## Build

From the repository root:

```bash
nix build .#ryoku-iso
```

The resulting ISO is under `result/iso/`.
