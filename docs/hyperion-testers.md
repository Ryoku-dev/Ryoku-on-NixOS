# Testing Hyperion v2 on NixOS

Hyperion is an experimental preview for flake-based Ryoku on NixOS.
No invitation code, GitHub account, or organisation membership is needed.

## Enter

For the Niri-only desktop, run this single command as your normal user:

```bash
nix run 'github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos?dir=nix/bootstrap' -- slim
```

Use `-- enter` instead of `-- slim` to keep the other compositors. The command
updates the Ryoku flake input and sets Hyperion options for the selected host.
It supports Ryoku configured in an imported NixOS module. Existing configuration
is backed up and restored if the build or activation fails. Switching requires
sudo authorization and can download or build substantial dependencies.

Preview the exact file edits without switching by using `-- plan` instead.

The `?dir=nix/bootstrap` flake evaluates only the onboarding command and one
pinned nixpkgs, never the desktop. It is the same command as `#ryoku-v2` of
the main flake.

## Apps

The desktop, Ryogami, Niri, RyoStore and Rashin are part of the system. The
apps Arch Hyperion treats as optional are in your own Nix profile, managed by
RyoMarket's Hyperion edition: Ryotunes 2.0, Ryoport, RyoManager, waifu2x and
QMK HID. The first Hyperion login installs Ryotunes, Ryoport, RyoManager and
waifu2x once; remove any of them in RyoMarket and they stay removed. Older
Ryotunes copies (RyoMarket profiles, `~/.local/bin` links, stale menu entries)
are moved to `~/.local/state/ryoku/nix/backups/<time>/ryotunes-legacy`, and
your library, settings and sign-ins carry over.

## Update an existing Hyperion installation

Once the Ryoku team publishes a tested update to the Hyperion branch, run:

```bash
ryoku-nix-update update
```

Once the NixOS CLI routing fix is installed, `ryoku update` also uses this
backend. Older Hyperion builds can still launch the Arch updater, so use the
explicit command for the first upgrade.

This follows the Hyperion branch already selected in `/etc/nixos`, updates
its locked Ryoku input, builds and switches the NixOS generation, and restores
the previous lock and active generation if activation fails. It does not
switch you to main or unstable-dev. Keep the previous NixOS boot generation
available until the updated desktop has been tested after login.

## Leave or recover

- `ryoku-v2 leave` (installed with Hyperion) switches back to unstable.
- If a build or switch fails, the previous `flake.nix`, `flake.lock` and
  `ryoku.nix` are restored automatically and the running system is unchanged.
- If the new desktop does not start, pick the previous generation in the boot
  menu, then run `ryoku-v2 leave`.

## Errors

| Message | Meaning |
|---|---|
| `cannot identify exactly one modules list` | Your flake uses a custom host layout. No files were changed. Add the Hyperion option to that host's module manually. |
| `channel switch build failed; previous flake files restored` | Nothing changed. Report the build log above the message. |
