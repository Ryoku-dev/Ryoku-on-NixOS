{ lib, ... }:

{
  # Ryoku ISO live-session / installer profile.
  #
  # The first console login launches the same guided terminal installer used
  # on an existing NixOS host, but in its dedicated full-install mode. Closing
  # it returns to the normal live shell for recovery/manual work.
  environment.loginShellInit = lib.mkAfter ''
    if [ "''${USER:-}" = "nixos" ] \
      && [ -z "''${SSH_TTY:-}" ] \
      && [ "$(tty 2>/dev/null || true)" = "/dev/tty1" ] \
      && [ ! -e /tmp/.ryoku-iso-installer-started ]
    then
      touch /tmp/.ryoku-iso-installer-started

      if command -v ryoku-install >/dev/null 2>&1; then
        ryoku-install --iso || true
        printf '\nRyoku installer closed. You are now in the live shell.\n'
        printf 'Run `ryoku-install --iso` to open it again.\n\n'
      fi
    fi
  '';

  # The maintainer-owned live desktop, branding, wallpaper, graphical terminal
  # launcher and hardware convenience packages can be layered here later
  # without changing the disk-install transaction itself.
}
