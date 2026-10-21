# Ryoku on NixOS system configuration.
# Help: https://search.nixos.org/options
# Ryoku: https://github.com/aethctl/Ryoku-on-NixOS

{ lib, pkgs, install, ... }:

let
  gpuModule = vendor: ./hardware/gpu/${vendor}.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ./hardware/gpu/common.nix
    ./pkgs.nix
  ] ++ map gpuModule install.gpuVendors;

  # ──────────────────────────────────────────────────────────────────────────
  # Boot
  # ──────────────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = install.firmware == "uefi";
  boot.loader.efi.canTouchEfiVariables = install.firmware == "uefi";

  boot.loader.grub.enable = install.firmware == "bios";
  boot.loader.grub.devices = lib.optionals (install.firmware == "bios") [
    install.installDisk
  ];

  # The installer records a stable kernel policy instead of a concrete version.
  # The selected package set is still pinned by this flake's nixpkgs input.
  boot.kernelPackages = {
    default = pkgs.linuxPackages;
    latest = pkgs.linuxPackages_latest;
    zen = pkgs.linuxPackages_zen;
  }.${install.kernel};

  # ──────────────────────────────────────────────────────────────────────────
  # Machine identity / networking
  # ──────────────────────────────────────────────────────────────────────────
  networking.hostName = install.hostname;
  networking.networkmanager.enable = true;

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ──────────────────────────────────────────────────────────────────────────
  # Locale / input
  # ──────────────────────────────────────────────────────────────────────────
  time.timeZone = install.timeZone;
  i18n.defaultLocale = install.locale;

  services.xserver.xkb = {
    layout = install.keyboardLayout;
    variant = "";
  };

  # ──────────────────────────────────────────────────────────────────────────
  # Nix
  # ──────────────────────────────────────────────────────────────────────────
  nix.package = pkgs.nixVersions.latest;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  nix.settings.auto-optimise-store = true;
  zramSwap.enable = true;

  # ──────────────────────────────────────────────────────────────────────────
  # User
  # ──────────────────────────────────────────────────────────────────────────
  users.users.${install.username} = {
    isNormalUser = true;
    description = install.username;
    extraGroups = [
      "audio"
      "input"
      "networkmanager"
      "video"
      "wheel"
    ];
    # Keep the password hash out of the world-readable Nix store. The ISO
    # installer writes this root-only file before the first activation.
    hashedPasswordFile = "/etc/ryoku/user-password.hash";
  };

  # ──────────────────────────────────────────────────────────────────────────
  # NixOS quality-of-life helpers
  # ──────────────────────────────────────────────────────────────────────────
  programs.fish.shellFunctions = {
    rebuild = {
      body = ''
        sudo nixos-rebuild switch --flake /etc/nixos#ryoku
      '';
    };

    update = {
      body = ''
        sudo nix flake update --flake /etc/nixos
        sudo nixos-rebuild switch --flake /etc/nixos#ryoku
      '';
    };

    clean = {
      body = ''
        sudo nix-collect-garbage -d
      '';
    };

    nixos = {
      body = ''
        cd /etc/nixos
      '';
    };

    configuration = {
      body = ''
        sudo -E nvim /etc/nixos/configuration.nix
      '';
    };

    flake = {
      body = ''
        sudo -E nvim /etc/nixos/flake.nix
      '';
    };

    pkgs = {
      body = ''
        sudo -E nvim /etc/nixos/pkgs.nix
      '';
    };
  };

  system.stateVersion = "26.11";
}
