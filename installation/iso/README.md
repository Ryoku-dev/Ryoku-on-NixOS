# installation/iso/

The Ryoku live ISOs. The Arch image starts from the official Arch `releng`
profile; the CachyOS variant stages that same profile into a CachyOS live
system. Both have one job: boot a machine and drop you straight into the Ryoku
installer.

## What it does at boot

1. The kernel and the archiso initramfs bring up the live system from the
   squashfs.
2. `agetty` logs root in automatically on the first console (tty1), with no
   password.
3. The login shell runs `ryoku-installer-session`, which starts a tiny Wayland
   kiosk (`cage`) running a terminal (`foot`) that runs the installer
   (`ryoku-tui`).
4. The TUI collects your answers and hands them to the backend (`ryoku-install`),
   which partitions, formats, installs the base system with `pacstrap`, and sets
   up the bootloader.

The graphical session only ever draws text, so it uses software rendering
(`WLR_RENDERER=pixman`) and works in VMs and on machines without working GPU GL.
The reason for `cage` + `foot` instead of the bare kernel console is color: the
kernel VT has 16 colors and no Nerd Font glyphs, so the TUI would fall back to
plain ASCII. `foot` gives it a truecolor terminal with the JetBrains Mono Nerd
Font, which is what the TUI is designed for.

If the installer crashes, the session relaunches it so the console never drops to
a bare prompt mid-install. A clean quit returns you to a root shell.

The serial console (ttyS0) and any other VT stay a plain root shell, so headless
or recovery use still works: set the `RYOKU_*` answers and run `ryoku-install`
by hand (the payload it reads is at `/usr/share/ryoku`).

## Variants: plain and CachyOS

`build.sh` takes `RYOKU_VARIANT` (default `plain`) and bakes the choice into the
airootfs at `/usr/share/ryoku/variant`. Both variants are fully offline (the
package closure is baked into a `file://` `[offline]` repo) and use the same TUI
and backend:

- **plain** is the Arch edition. Its live system boots `linux`, and its target
  installs Arch plus the Ryoku desktop.
- **cachyos** is the CachyOS edition from the live kernel onward. In the
  throwaway profile, `stage-variant.sh` replaces `linux` with
  `linux-cachyos`, adds `cachyos-keyring`, the CachyOS mirrorlists,
  `cachyos-hooks`, and `chwd`, places generic `[cachyos]` above `[core]`, and
  rewrites the mkinitcpio and UEFI, BIOS, GRUB, and syslinux boot paths. The ISO
  application name and `/etc/motd` identify the CachyOS edition.

The installed CachyOS target also resolves against generic `[cachyos]` above
Arch's repositories. It receives the CachyOS kernel pair, repositories, tuning,
hooks, tools, and identity, with the Ryoku desktop on top. The install remains
fully offline. On the first full update, CachyOS's target repository
configuration moves CPUs with a supported optimized tier onto that tier's
builds.

`stage-variant.sh` only edits the staged profile copy. The committed profile
remains generic, and staging the plain variant leaves it byte-for-byte
unchanged.

CI builds both variants from the same tree: `build-iso.yml` (plain) and
`build-iso-cachyos.yml` (cachyos) each call the reusable
`build-iso-reusable.yml`. Separate workflows keep independent run counters, so
the tracking id is per variant (plain `r164`, cachyos `r1`), and each publishes
its own `latest*.json` pointer to R2.

## What is baked in

The committed profile holds only the live environment definition. The installer
itself and the repo payload are added by `build.sh` at build time, so binaries
are never committed here.

Live environment packages (`packages.x86_64`): the base system and kernel, the
archiso boot hooks, both bootloaders (syslinux for BIOS, systemd-boot for UEFI),
the backend toolchain (partitioning, filesystems, pacstrap, Limine),
NetworkManager + iwd for Wi-Fi, and `cage` + `foot` + the Nerd Font for the
installer session. There is no Go toolchain on the ISO: the TUI ships prebuilt.

The target system's own packages are not in this list. The backend installs them
with `pacstrap` from `system/packages` at install time.

## On-ISO layout

What `build.sh` places into the image:

```
/usr/local/bin/ryoku-tui                  the prebuilt installer TUI (Go)
/usr/local/bin/ryoku-install              wrapper: execs the backend below
/usr/local/bin/ryoku-installer-session    the cage + foot + ryoku-tui launcher
/usr/local/lib/ryoku/backend/ryoku-install   the real backend script
/usr/local/lib/ryoku/backend/lib/*           the backend's library (sourced)
/usr/share/ryoku/                         the repo payload (RYOKU_REPO)
```

The backend finds its `lib/` by resolving the real path of its own script, so the
real script and its `lib/` must live together. They do, under
`/usr/local/lib/ryoku/backend`. The `/usr/local/bin/ryoku-install` wrapper just
`exec`s the real script, so `realpath` still points at the backend directory and
the library is found. The installer session exports `RYOKU_REPO=/usr/share/ryoku`
and `RYOKU_BACKEND=ryoku-install`, which is how the TUI locates both the payload
and the backend on `PATH`.

## Building it

`build.sh` does everything: it stages a throwaway copy of this profile, applies
the selected edition with `stage-variant.sh`, builds the TUI from `../tui`,
bakes the TUI, backend, and repository into the staged airootfs, and then runs
`mkarchiso`. The committed profile is never modified.

Requirements on the build host: `go` (the TUI and Go daemons), `cmake`, `ninja`,
and the Qt6 development libraries (qt6-base, qt6-declarative,
qt6-shadertools; the Ryoku.Blobs plugin), `archiso` (for `mkarchiso`), `curl`
and `bsdtar`, and root (mkarchiso needs it).

Before a CachyOS build invokes `mkarchiso`, it establishes CachyOS package trust
on the build host without a keyserver. It fetches `cachyos-keyring` over TLS,
checks the package SHA-256 against the generic repository metadata, verifies
the pinned fingerprint
`882DCFE48E2051D48E2562ABF3B607488DB35A47`, installs the keyring files, and
runs `pacman-key --populate cachyos`. A mismatch stops the build.

```
cd installation/iso
./build.sh
```

The ISO lands in `installation/iso/out/`. To stage everything but stop before
`mkarchiso` (useful without root):

```
./build.sh --stage-only
```

The payload under `/usr/share/ryoku` is baked from `HEAD`. To test uncommitted
work, bake the working tree instead (no commit is made):

```
RYOKU_ISO_WORKTREE=1 ./build.sh
```

If `mkarchiso` is missing, `build.sh` stages the profile and prints the exact
command to finish by hand:

```
sudo --preserve-env=SOURCE_DATE_EPOCH mkarchiso -v -w work -o out ./staging/profile
```

Output, work, and staging directories live under `installation/iso/` and are
git-ignored, as is the package cache the offline bake keeps per variant
(`offline-cache-plain`, `offline-cache-cachyos`) so a rebuild downloads only
what changed.

`tests/iso-variant-stage.sh` is the focused gate for this split. It checks that
plain staging is unchanged and CachyOS staging has the expected packages,
repository order, kernel boot paths, edition labels, and idempotent output.
`installation/tests/iso-preflight.sh` runs it with the other ISO gates.

## Booting it

Write the ISO to a USB stick with `dd` (or **Rufus in DD mode** on Windows):

```
dd if=ryoku-<date>-x86_64.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**Ventoy is supported.** Ventoy does not write the ISO to a disk; it presents the
ISO file as a virtual block device. In UEFI it hooks the firmware block-I/O
protocol and chainloads the ISO's own systemd-boot; once the kernel is up its
initramfs hook recreates the mapping with device-mapper (`vtoydm`/`dmsetup`). The
virtual device carries the ISO's own label, so archiso's `archisosearchuuid`
finds the squashfs and the live session runs the same as a raw `dd` write. The
boot entries carry `cow_spacesize=1G`, so the live writable overlay is a 1 GiB
tmpfs (larger than archiso's 256 MiB default, which a long install can exhaust
into "no space left" errors). Ventoy's default (normal) mode is the primary
path for this systemd-boot ISO. When that device-mapper injection fails on a
given firmware -- archiso then waits for a medium that never appears and drops to
an initramfs rescue prompt where the USB keyboard is often dead -- boot the ISO
in Ventoy's **GRUB2 mode** (its secondary boot menu, or `Ctrl+r`). That mode
reads `grub/loopback.cfg` from the image and boots by file with `img_dev`/
`img_loop` instead of a label search, so `archiso_loop_mnt` mounts the ISO
directly. A raw `dd` / Rufus-DD write to a dedicated stick is the last resort if
a machine's firmware balks at Ventoy's shim entirely.

Both firmware paths (UEFI systemd-boot, BIOS syslinux) expose the same three
entries; the default is always the first:

1. **Ryoku Linux installer** -- the normal boot with kernel mode-setting on. The
   installed NVIDIA system already gets `nvidia_drm.modeset=1` on its own
   cmdline; this is the live-image default.
2. **… (safe graphics)** -- adds `nomodeset`. Use it when the screen goes black
   or garbled at boot; some laptop GPUs need it to reach the installer at all.
3. **… (copy to RAM, slow USB)** -- adds `copytoram`, loading the whole image
   into RAM before boot so the install runs without the stick. Slow to start on
   a slow stick, but resilient to a flaky or removed drive.

## Reproducibility

`build.sh` pins every timestamp-bearing step to the commit's committer date via
`SOURCE_DATE_EPOCH` (from `git log -1 --pretty=%ct`), which `mkarchiso`, `tar`,
`gzip`, and the squashfs writer all honor; `profiledef.sh` reads the same value
for `iso_label` (`RYOKU_<YYYYMM>`) and `iso_version` (`<YYYY.MM.DD>`). The three
prebuilt Go binaries (the TUI, `ryoku-shell`, `ryoku-hub`) build with
`-trimpath`, `-ldflags '-s -w -buildid='`, and `CGO_ENABLED=0`, and each module
pins its compiler with a `toolchain` line, so a fixed commit plus toolchain
yields byte-identical binaries. After `mkarchiso` finishes, `build.sh` writes
`SHA256SUMS` next to the ISO.

What is deterministic *when*: given the same commit and Go toolchain, the staged
tree and the prebuilt binaries are byte-identical -- this is exactly what
`installation/tests/iso-stage-check.sh` verifies (it stages twice and diffs).
The *packages* baked into the image are not deterministic by default: the build
pulls whatever the live Arch mirrors serve that day, so an image built weeks
later differs by upstream churn. Set `RYOKU_ISO_REPRO=1` to repoint the staged
`pacman.conf`'s `[core]`/`[extra]` at the Arch Linux Archive snapshot dated from
the commit (`archive.archlinux.org/repos/<YYYY/MM/DD>`), freezing the exact
package versions. Reproducible here means *frozen*, not *latest* -- use it only
to reproduce a specific historical ISO, never for a normal release build.

## Version skew: the ISO vs the [ryoku] repo

A live ISO is a snapshot: it bakes the repo payload (`/usr/share/ryoku`) and the
prebuilt binaries from one commit, but the target it installs pulls Ryoku
packages from the live `[ryoku]` pacman repo, which keeps moving. Two mechanisms
keep an old ISO usable against a newer repo:

- **Payload stamp.** `build.sh` writes `/usr/share/ryoku/.payload` with the
  commit hash, commit date, and `VERSION` (e.g. `0.4.7-beta.17`) the image was
  built from, and fills the same values into the live `/etc/motd`. The install's
  deploy step reads the stamp and warns -- never fatally -- when the baked
  payload's version has drifted from the `ryoku-desktop` version the live repo
  now serves, so a months-old USB stick surfaces the skew instead of silently
  mixing eras.
- **Umbrella-package indirection.** The deploy step installs the umbrella meta
  packages (`ryoku-keyring`, `ryoku-desktop`) rather than a hand-listed set. The
  umbrella PKGBUILD version-pins every monorepo component, so an old ISO that
  only knows the umbrella name still survives component renames, splits, and
  additions in a newer repo -- the indirection absorbs the churn.
