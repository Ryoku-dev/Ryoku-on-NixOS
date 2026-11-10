# Testing Hyperion v2 on NixOS

Hyperion is a preview channel. You need a flake-based NixOS system (the Ryoku
installer creates one in `/etc/nixos`) and an invitation code from the Ryoku
team. No GitHub account is needed.

## Enter

```bash
nix run 'github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos?dir=nix/bootstrap' -- authorize
nix run 'github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos?dir=nix/bootstrap' -- plan
nix run 'github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos?dir=nix/bootstrap' -- slim
```

1. `authorize` asks for the invitation code and stores it, readable only by
   you, in `~/.config/ryoku/hyperion-invite`. Run it as the desktop user, not
   with `sudo`.
2. `plan` prints the exact `/etc/nixos` changes without making them.
3. `slim` switches to the Niri-only Hyperion desktop; `enter` keeps the other
   compositors. Both ask for your password once to build and switch.

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

## Leave or recover

- `ryoku-v2 leave` (installed with Hyperion) switches back to unstable.
- If a build or switch fails, the previous `flake.nix`, `flake.lock` and
  `ryoku.nix` are restored automatically and the running system is unchanged.
- If the new desktop does not start, pick the previous generation in the boot
  menu, then run `ryoku-v2 leave`.

## Errors

| Message | Meaning |
|---|---|
| `no valid Hyperion invitation is stored` | Run `authorize` again as your user; codes expire. |
| `invalid or expired Hyperion invitation` | The code was mistyped or has expired; ask for a new one. |
| `needs exactly one programs.ryoku.enable = true; declaration` | Ryoku is enabled in an unusual place; add `programs.ryoku.hyperionPackages.enable = true;` yourself. |
| `channel switch build failed; previous flake files restored` | Nothing changed. Report the build log above the message. |
