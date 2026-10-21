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
The other files stay clean and user-editable. The installed `flake.nix` keeps
moving branch URLs: `nixos-unstable` for Nixpkgs and the branch the ISO was
built from for Ryoku (`unstable-dev` for `ryoku-iso`, `main` for
`ryoku-iso-stable`). The generated `flake.lock` pins both to the exact revisions
in the image, so a later `nix flake update` advances along that branch.
`ryoku track stable|unstable` switches the branch afterwards.

`ryoku.nix` also enables `programs.ryoku.graphics.matchRyokuMesa`. The
installed system's nixpkgs is newer than Ryoku's own package set, and Ryoku's
compositors crash at startup when they load a Mesa built against a newer glibc,
so the system's GL driver comes from Ryoku's set.

Rebuild an installed system with:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#ryoku
```

## Build

From the repository root:

```bash
nix build .#ryoku-iso
```

The resulting ISO is under `result/iso/`. Its name carries the channel and the
source revision, for example
`ryoku-nixos-0.103.5-beta.20-unstable-dev-586140e-x86_64-linux.iso`.
`.#ryoku-iso-stable` builds the same image for installs that follow `main`.

To build the newest `unstable-dev` without a checkout:

```bash
nix build github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev#ryoku-iso
```

## Automated builds

The `NixOS ISO build` workflow builds the ISO on every push to `unstable-dev`
(and `main`), boots it, and uploads it with its SHA-256 as a workflow artifact
for 14 days. On the same pushes it builds `.#ryoku-install-closure`, what a
default guided install needs, and pushes it to the Ryotunes Cachix cache. The
installer already trusts that cache, so installs download Ryoku's own packages
instead of compiling them. The `NixOS ISO` workflow runs the installer checks
and the boot test on pull requests that touch the installer or the ISO.

## Tests

- `checks.x86_64-linux.ryoku-iso-boot` boots the ISO with UEFI and with legacy
  BIOS, checks that the guided installer opens on tty1, verifies the live
  store, and checks that an unattended dry run renders a flake that follows
  the ISO's branch. It runs offline in the build sandbox.
- `nix run .#ryoku-iso-install-test` installs Ryoku from the ISO onto an empty
  VM disk, boots the result, logs in through the qylock SDDM greeter and checks
  that Hyprland and niri start with the Ryoku shell. It needs KVM, network and
  a host GPU render node (the installed desktop renders through virgl) and
  takes about an hour; `RYOKU_VM_CORES` and `RYOKU_VM_MEMORY` (MiB) size the VM.

Both tests use the release image plus NixOS' test instrumentation, which only
adds the test driver's backdoor shell, packed with a faster squashfs level.
