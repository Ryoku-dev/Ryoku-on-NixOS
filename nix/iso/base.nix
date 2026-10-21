{
  self,
  pkgs,
  lib,
  modulesPath,
  ryokuRepo,
  ryokuIsoChannel ? "unstable-dev",
  ryokuIsoNixpkgsRev ? "",
  ryokuIsoRyokuRev ? "",
  ...
}:

let
  # Release images carry their Git revision; dirty development trees do not.
  sourceLabel = self.shortRev or self.dirtyShortRev or "dirty";
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-base.nix"
  ];

  # ──────────────────────────────────────────────────────────────────────────
  # Ryoku ISO identity
  # ──────────────────────────────────────────────────────────────────────────
  networking.hostName = "ryoku-live";

  image.baseName = lib.mkForce
    "ryoku-nixos-${self.lib.version}-${ryokuIsoChannel}-${sourceLabel}-${pkgs.stdenv.hostPlatform.system}";

  isoImage = {
    volumeID = lib.mkForce "RYOKU_NIXOS";
    makeEfiBootable = true;
    makeUsbBootable = true;
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Modern Nix baseline
  # ──────────────────────────────────────────────────────────────────────────
  # The live image is intentionally flake-native. Keep the Nix implementation
  # current even when the installer profile itself stays pinned and reproducible.
  nix.package = pkgs.nixVersions.latest;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Give the installer compressed emergency headroom. The full Ryoku closure
  # includes a few memory-hungry builds, and the live environment should not
  # OOM-kill nixos-install on otherwise-supported 8 GiB machines.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
  };

  # The source tree embedded in the image is the exact revision used to build
  # it. Installer/profile code can therefore install that revision rather than
  # silently chasing a moving Git branch.
  environment.etc."ryoku/source".source = self;
  environment.sessionVariables = {
    RYOKU_INSTALL_SOURCE = "path:/etc/ryoku/source";

    # A clean release ISO installs the exact revisions used to build the
    # image. Dirty development images deliberately fall back to their embedded
    # Ryoku source so the installer never claims an older Git commit matches
    # uncommitted code in the image.
    RYOKU_INSTALL_TARGET_SOURCE =
      if ryokuIsoRyokuRev != ""
      then "${ryokuRepo}/${ryokuIsoRyokuRev}"
      else "path:/etc/ryoku/source";

    # The installed flake follows the branch this image was built from, so
    # `nix flake update` on an unstable-dev install stays on unstable-dev.
    RYOKU_INSTALL_TARGET_TRACK = "${ryokuRepo}/${ryokuIsoChannel}";

    RYOKU_INSTALL_NIXPKGS_SOURCE =
      if ryokuIsoNixpkgsRev != ""
      then "github:NixOS/nixpkgs/${ryokuIsoNixpkgsRev}"
      else "github:NixOS/nixpkgs/nixos-unstable";
  };
  nix.registry.ryoku.flake = self;

  # ──────────────────────────────────────────────────────────────────────────
  # Live installation toolbox
  # ──────────────────────────────────────────────────────────────────────────
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    bash
    coreutils
    curl
    git
    gnugrep
    jq
    nixVersions.latest
    nixos-install-tools
    networkmanager
    whois
    parted
    rsync
    util-linux
  ];

  # Useful both for hand-testing the ISO and for whatever installer frontend
  # the profile grows later. installation-cd-base already supplies the live
  # nixos user and installer-oriented sudo policy.
  services.openssh.enable = true;

  system.stateVersion = "26.11";
}
