<div align="center">

<img src="docs/readme/assets/brand/ryoku-header.jpg" alt="Ryoku" width="850" />

---

### 力と美のために
**The Ryoku you already know, made declarative for NixOS.**

Ryoku on NixOS is the official NixOS port of [**Ryoku**](https://github.com/Ryoku-dev/ryoku),
a complete Wayland desktop with deep customisation, integrated applications and the best and most expansive ecosystem to ever be made on a shell.

[**Website**](https://aethctl.github.io/Ryoku-on-NixOS/) · [**Install on NixOS**](#install) · [**Installer ISO**](https://github.com/aethctl/Ryoku-on-NixOS/releases) · [**Discord**](https://discord.gg/xvr69NRsmt) · [**Documentation**](docs/README.md) · [**Upstream Ryoku**](https://github.com/Ryoku-dev/ryoku)

<br />

**Beauty on the surface. Nix underneath.**

The shell, Hub, launcher, RyoStore, theming and Ryoku applications are identical to its Arch counterpart while
NixOS specific packaging, modules, system bridges, installer behavior and updates remain declarative.

> **v1 is currently in active beta.** The existing NixOS install script is the recommended route however,
> the bootable ISO is available for testing from GitHub Releases but it **will erase the selected disk** during installation as is currently
> doesnt support manual partitioning.

</div>

---

## The desktop

<table>
  <tr>
    <td width="50%">
      <img src="docs/readme/assets/ui/desktop.png" alt="Ryoku desktop" width="100%" />
      <br />
      <sub><b>Desktop.</b> Aesthetic by default and heavily customisable.</sub>
    </td>
    <td width="50%">
      <img src="docs/readme/assets/ui/launcher.webp" alt="Ryoku launcher" width="100%" />
      <br />
      <sub><b>App Launcher.</b> Apps, commands, files, packages, calculator and more in one launcher.</sub>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="docs/readme/assets/ui/controls.webp" alt="Ryoku controls" width="100%" />
      <br />
      <sub><b>Controls.</b> Session, connectivity, sound, brightness, media and power in one sidebar.</sub>
    </td>
    <td width="50%">
      <img src="docs/readme/assets/ui/profile.webp" alt="Ryoku profile page" width="100%" />
      <br />
      <sub><b>Profile.</b> The most customizable configuration profile page in any shell</sub>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="docs/readme/assets/ui/hub-page.webp" alt="Ryoku Hub" width="100%" />
      <br />
      <sub><b>Ryoku Hub.</b> System information, settings and Ryoku specific controls in one place.</sub>
    </td>
    <td width="50%">
      <img src="docs/readme/assets/ui/batgirl.webp" alt="Ryoku themed desktop" width="100%" />
      <br />
      <sub><b>Matugen.</b> No matter the wallpaper, components recolour themselves around it.</sub>
    </td>
  </tr>
</table>

### Customise it your way

Ryoku is designed to be incredibly customizable out of the box with the easy to use Ryostore and Settings page

<table>
  <tr>
    <td width="50%"><img src="docs/readme/assets/showroom/torii-sunset.webp" alt="Ryoku desktop with a Japanese sunset landscape" width="100%" /></td>
    <td width="50%"><img src="docs/readme/assets/showroom/monochrome-hands.webp" alt="Monochrome Ryoku desktop with widgets and ASCII artwork" width="100%" /></td>
  </tr>
  <tr>
    <td width="50%"><img src="docs/readme/assets/showroom/blue-clouds.webp" alt="Blue Ryoku desktop with a minimal launcher and media widget" width="100%" /></td>
    <td width="50%"><img src="docs/readme/assets/showroom/monochrome-anime.webp" alt="Monochrome Ryoku desktop with large typography and system widgets" width="100%" /></td>
  </tr>
</table>

---

<div align="center">

<img src="docs/readme/assets/art/beauty.png" alt="Power" width="70%" />

</div>

## What this port owns

Ryoku's base code and configs are the same as upstream, this
repository is simply the NixOS adaptation. Packaging, module integration, installer and
update behavior, service wiring, compatibility fixes and Nix specific runtime
bridges.

That gives the same desktop two different system foundations:

<table>
  <tr>
    <td width="50%" valign="top">
      <b>Ryoku on Arch</b><br /><br />
      Pacman and AUR integration<br />
      Arch-native services and system tooling<br />
      Arch update and recovery flow
    </td>
    <td width="50%" valign="top">
      <b>Ryoku on NixOS</b><br /><br />
      Nix packages and NixOS modules<br />
      Declarative packaging and integration<br />
      NixOS generations and rollback
    </td>
  </tr>
</table>

---

<div align="center">

<img src="docs/readme/assets/art/power.png" alt="Power" width="70%" />

</div>

## Ryoku's power made declarative

<table>
  <tr>
    <td width="33%" valign="top">
      <h3>Declarative</h3>
      Packages, services and desktop integration are expressed through NixOS rather
      than copied into mutable system locations.
    </td>
    <td width="33%" valign="top">
      <h3>Reproducible</h3>
      The flake input adds all of the Ryoku modules, packages, installer, development
      environment (nix dev/ nix build) all from one single input.
    </td>
    <td width="33%" valign="top">
      <h3>Recoverable</h3>
      Updates produce a new NixOS generation and switches to it automatically so the normal NixOS rollback model
      remains available.
    </td>
  </tr>
</table>

---

<div align="center">

<img src="docs/readme/assets/art/torii.png" alt="Ryoku ecosystem" width="100%" />

</div>

## The Ryoku ecosystem

Ryoku is more than the shell. The desktop is built from a set of focused tools
that share the same visual and interaction language.

<table>
  <tr>
    <td width="33%" valign="top">
      <b>Ryostore</b><br />
      Themes, bar styles, Fastfetch presets, lockscreens, plugins and decor all easily installable to customize your desktop.
    <td width="33%" valign="top">
      <b>Ryotunes</b><br />
      Native playback and music integration with YT Music, Spotify and SoundCloud all designed around the Ryoku desktop.
    </td>
    <td width="33%" valign="top">
      <b>RyoMotion</b><br />
      Screen recording and advanced video/ screenshot editing integrated with Ryoku's capture workflow.
    </td>
  </tr>
  <tr>
    <td width="33%" valign="top">
      <b>Ryogami</b><br />
      Wallpaper and visual tooling that feeds the wider Ryoku theme system with Wallpaper Engine and external repo support.
    </td>
    <td width="33%" valign="top">
      <b>Rashin</b><br />
      Ryoku's assistant and terminal facing intelligence layer, compatable with Hermes, locally hosted AI and API models.
    </td>
    <td width="33%" valign="top">
      <b>Ryoku Hub</b><br />
      Customizable profile, in depth settings, Fastfetch customizer, WM options and desktop control from one integrated surface.
    </td>
  </tr>
</table>

---

<div align="center">

<img src="docs/readme/assets/art/hero.png" alt="Ryoku on NixOS" width="50%" />

</div>

## Installing Ryoku on NixOS

There are two installation paths.

### Existing NixOS system

For an existing **flake-based NixOS system**, start the guided installer as your normal user

```bash
nix run github:aethctl/Ryoku-on-NixOS/main#install
```

Choose your compositor, browser, shell and optional apps, then review the generated changes before installation begins.

The installer:

- adds Ryoku to your existing flake,
- creates the `ryoku.nix` modules,
- updates `flake.lock`,
- builds a new generation,
- switches to the new generation only after the build succeeds,
- restores the previous configuration files if the integration fails.

For custom flake paths, multi-host setups and manual integration, see the
[**NixOS guide**](docs/nixos.md).

### Fresh install / ISO

The bootable Ryoku on NixOS installer ISO is currently in **pre-release testing** ahead of v1.
It is intended to become the primary path for fresh installations.

[**View installer ISO releases →**](https://github.com/aethctl/Ryoku-on-NixOS/releases)

> **Testing warning:** installation **will erase the selected disk**. Back up anything important before using a pre-release ISO.

## Requirements

Ryoku is `x86_64` only and boots in UEFI mode. The session is Wayland on
Hyprland or niri, with the GPU-composited Ryoku shell on top. The installer
refuses a machine with Secure Boot on (Limine ships unsigned) unless you have
enrolled your own keys, and there is no 32-bit build and no legacy BIOS path.

|  | Minimum | Recommended |
|---|---|---|
| CPU | 64-bit x86_64, dual-core | quad-core or better |
| RAM | 4 GB | 8 GB, 16 GB with the dev toolchains |
| GPU | any card with working KMS and OpenGL/Vulkan | recent integrated or discrete |
| Storage | 32 GB (installer floor) | 64 GB+ SSD |
| Firmware | UEFI, Secure Boot off | UEFI, Secure Boot off |

---

## What ships

| Area | What it contains |
| --- | --- |
| `ryoku/` | Shared Ryoku desktop, shell, applications, Hyprland integration and assets |
| `nix/` | Nix packages, NixOS module, installer, system bridge and Nix-specific integration |
| `flake.nix` | Public Nix entry point for modules, packages, apps, checks and development |
| `docs/` | Shared desktop docs, NixOS docs and upstream Arch reference material |
| `tests/` | Focused validation for the port and shared desktop behavior |

The repository is intentionally split between `/ryoku` and `/nix`. Shared desktop
features are located in `/ryoku`. Nix specific files, modules and compatability layers live in `nix/`.

The Nix layer packages the major Ryoku components independently rather than
treating the desktop as one wrapper. The root flake exposes the shell,
Hub, CLI, Ryostore, Ryotunes, Ryogami, RyoMotion, helper packages, compositor
integration and the combined bundle as separate outputs.

---

## How the port is maintained

This is a maintained platform port, not a one-time source translation. Upstream
changes are reviewed and are ported within 2 days of upstream release.

1. Shared desktop and application changes stay in `ryoku/` whenever possible.
2. Arch specific packages, servicse and filesystem assumptions are replaced with
   Nix packages, NixOS modules or narrow runtime bridges.
3. Bugs that also affect upstream Ryoku are fixed upstream when practical, fixes
   that only exist because of NixOS being NixOS stay in this repo.
4. Visible runtime changes are tested on NixOS before they are released.

The detailed ownership rules and sync workflow live in
[**docs/maintenance.md**](docs/maintenance.md).

---

## Validation

The public flake makes the core port buildable through one entry point

```bash
nix flake check
```

Its checks build the main runtime packages, QML modules, desktop integration,
installer and materializer, and run focused installer/parser checks. CI adds
shell linting, QML linting, Go tests, installer safety checks and targeted
integration guards.

For compositor, display, audio, GPU or installer behavior, a green CI run is not
treated as runtime proof. Pull requests should record the machine/runtime test
that was actually performed.

---

## Community and contributing

Ryoku on NixOS is actively maintained and contributions are welcome.

- [**Join the Ryoku Discord**](https://discord.gg/xvr69NRsmt) for installation help, testing and development discussion.
- [**Browse open issues**](https://github.com/aethctl/Ryoku-on-NixOS/issues) for current work.
- [**Start with a good first issue**](https://github.com/aethctl/Ryoku-on-NixOS/issues?q=is%3Aissue%20state%3Aopen%20label%3A%22good%20first%20issue%22) if you want a bounded first contribution.
- Read [**CONTRIBUTING.md**](CONTRIBUTING.md) for the development workflow, testing expectations and upstream/NixOS ownership boundary.
- Read the [**performance roadmap**](docs/roadmap.md) for measured shell-performance work that needs contributors.

Testing is useful too. Hardware-facing changes cannot be proven by CI alone, so real reports from different GPUs, compositors and machines materially improve the port.

---

## Development

Clone the repository and enter the development shell:

```bash
nix develop
```

Run Ryoku directly from a development checkout:

```bash
nix run .#ryoku-dev
```

Useful public flake outputs include:

```text
.#install
.#ryoku-dev
.#ryoku-materialize
```

See [**docs/README.md**](docs/README.md) for the documentation map and
[**docs/structure.md**](docs/structure.md) for the repository layout.

---

## Upstream and credits

Ryoku on NixOS is the NixOS port of
[**Ryoku**](https://github.com/Ryoku-dev/ryoku).

Ryoku was created by [**Neur0map**](https://github.com/neur0map). The NixOS port
keeps upstream desktop behavior close while adapting system integration to NixOS.

Full attribution is available in [`NOTICE`](NOTICE).

**Ryoku is released under the [GNU GPL v3](LICENSE).**

---

<div align="center">

### 力と美のために

**Power in the system. Beauty in the surface.**

</div>
