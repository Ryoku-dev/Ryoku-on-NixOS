# Kernels and CachyOS gaming

Ryoku's Arch edition installs the stock Arch kernel by default. During setup,
**Gaming with CachyOS** can add CachyOS's kernel, tuning, schedulers, and gaming
stack. The same package set is available later from RyoStore as **CachyOS
Gaming**. Both paths keep the Arch kernel installed, but they differ in which
kernel boots first.

The CachyOS ISO is a separate edition. Its live system and installed system both
use CachyOS packages, repositories, identity, and kernels.

## What Gaming with CachyOS installs

The Arch installer's Gaming question defaults to No. Choosing Yes installs:

- `linux-cachyos` and `linux-cachyos-headers`
- `cachyos-settings`, including `ananicy-cpp` and
  `cachyos-ananicy-rules`
- `scx-scheds`
- `steam`
- `cachyos-gaming-meta`, which brings Proton-CachyOS SLR, Wine-CachyOS,
  `umu-launcher`, `winetricks`, and `protontricks`

This option needs an x86-64-v3 CPU and a working network connection. The TUI
disables it and explains why when either requirement is missing. If a repository
or package download fails after installation starts, Ryoku finishes the rest of
the install without the gaming layer. You can add it later from RyoStore.

The RyoStore bundle has the same package set. Its catalogue id remains
`cachyos-layer`, while the user-facing name is **CachyOS Gaming**.

## Why the Arch userland stays Arch

The helper adds both `[cachyos-v3]` and the generic `[cachyos]` repository.
`linux-cachyos` is in the v3 repository, while `cachyos-settings`, its Ananicy
rules, and the gaming packages are in the generic repository.

Both CachyOS repositories are placed below Arch's repositories and `[ryoku]` in
`pacman.conf`. Pacman takes a package from the first repository that provides
its name, so Arch remains authoritative for `glibc`, Mesa, `nvidia-utils`, SDDM,
zlib, and the rest of the Arch userland. CachyOS supplies only names the earlier
repositories do not have.

Older versions added only `[cachyos-v3]` above `[core]`. That layout could not
find the generic-repository packages, and a later full upgrade could replace
Arch packages with CachyOS builds. Running the current helper migrates that
layout by removing the old block and adding both repositories at the bottom. It
does not alter a CachyOS edition's native repository order.

The helper receives the CachyOS signing key from a keyserver when available and
checks its full pinned fingerprint. If the keyservers fail, it downloads
`cachyos-keyring` over TLS, verifies the package checksum from repository
metadata, checks fingerprint
`882DCFE48E2051D48E2562ABF3B607488DB35A47`, and imports that keyring.

## Which kernel boots

The installation path makes `linux-cachyos` the default and keeps Arch
`linux` as the fallback entry in Limine. On NVIDIA, it first makes sure the
CachyOS kernel has a working module:

- An Arch `nvidia-open` install gets `linux-cachyos-nvidia-open`.
- A DKMS install must build a module that `modinfo` can load for
  `linux-cachyos`.
- If neither path leaves a usable module, the packages stay installed but the
  Arch kernel remains the default.

The RyoStore path is intentionally less intrusive. The stock Arch kernel remains
the default after installation. Pick `linux-cachyos` in the Limine menu when you
want to try it; Limine's `remember_last_entry` setting keeps using the entry you
last chose.

Every DKMS module, including NVIDIA and VirtualBox modules, must build against
each installed kernel. Check the package transaction for build failures before
rebooting.

## Should you use it?

`linux-cachyos` is an x86-64-v3 kernel with the CachyOS patch set and sched-ext
support. `scx-scheds` provides userspace schedulers, while CachyOS's tuning and
Ananicy rules focus resources on the foreground workload. The difference is
most useful for games and heavy multitasking. A light desktop may not feel
different.

The cost is another upstream repository, another kernel image and initramfs in
`/boot`, and another kernel every DKMS module must support. The Arch kernel stays
available as the known-good path.

## Rollback

If the CachyOS kernel does not work:

1. Choose the Arch kernel in Limine.
2. Leave it selected. Limine remembers the last entry.
3. Remove **CachyOS Gaming** from RyoStore if you no longer want the added
   packages.

Pacman transactions are covered by Ryoku's Snapper hooks when snapshots are
enabled, so the pre-transaction snapshot is also available from Limine. Removing
the bundle does not need to remove its repository stanzas. They remain below
Arch and `[ryoku]`, so the Arch package set stays authoritative.

## The full CachyOS edition

Choose the CachyOS ISO when you want CachyOS as the base rather than an Arch
system with an optional gaming layer. The live image boots `linux-cachyos`,
trusts and uses the generic `[cachyos]` repository, and identifies itself as the
CachyOS edition. The installed target uses CachyOS's repository order, branding,
kernel pair, hooks, hardware tools, tuning, and desktop utilities underneath the
same Ryoku desktop.

Its Gaming question is smaller because the kernel and tuning already ship with
the edition. Yes keeps `steam` and `cachyos-gaming-meta`; No leaves both out.
The choice works offline from the ISO.
