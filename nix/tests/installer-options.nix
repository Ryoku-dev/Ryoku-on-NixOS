{ pkgs, module }:
let
  lib = pkgs.lib;

  baseline = {
    system.stateVersion = "26.05";
    networking.hostName = "ryoku-installer-test";
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    boot.loader.grub = {
      enable = true;
      devices = [ "/dev/vda" ];
    };
  };

  evaluate = extra: (import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      module
      baseline
      { programs.ryoku.enable = true; }
      extra
    ];
  }).config;


  fakeHomeManager = { lib, ... }: {
    options.home-manager.users = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
    };
  };

  evaluateWithHomeManager = extra: (import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      module
      fakeHomeManager
      baseline
      { programs.ryoku.enable = true; }
      extra
    ];
  }).config;

  ryokuOwnershipFailures = cfg:
    lib.filter
      (entry:
        !entry.assertion
        && lib.hasInfix "Home Manager must not manage Ryoku's mutable runtime state" entry.message)
      cfg.assertions;

  hmDesktopConflict = evaluateWithHomeManager {
    home-manager.users.mo = {
      home.file.".config/ryoku/desktop.json" = { text = "{}"; };
    };
  };

  hmShellConflict = evaluateWithHomeManager {
    home-manager.users.mo = {
      xdg.configFile."ryoku/shell.json" = { text = "{}"; };
    };
  };

  hmUserEditsAllowed = evaluateWithHomeManager {
    home-manager.users.mo = {
      xdg.configFile."ryoku/user_edits/hypr/modules/env.lua" = { text = "# override"; };
    };
  };

  defaults = evaluate { };
  slim = evaluate {
    programs.ryoku = {
      defaultCompositor = "niri";
      browser = "firefox";
      shell = "zsh";
      optionalApps = [ "prompt" "flatpak" "go" ];
    };
  };

  names = cfg: map lib.getName cfg.environment.systemPackages;
  manifest = cfg:
    builtins.fromJSON (
      builtins.unsafeDiscardStringContext
        cfg.environment.etc."ryoku/nix-integration.json".text
    );

  defaultNames = names defaults;
  slimNames = names slim;
  ryogamiPathNames = map lib.getName defaults.systemd.user.services.ryogami.path;
  plasmaCoexist = evaluate {
    services.desktopManager.plasma6.enable = true;
    services.displayManager.sddm.enable = true;
    services.displayManager.defaultSession = "plasma";
    programs.ryoku.defaultCompositor = "niri";
  };
  plasmaSessionNames = map lib.getName plasmaCoexist.services.displayManager.sessionPackages;
  slimManifest = manifest slim;
in
assert builtins.length (ryokuOwnershipFailures hmDesktopConflict) == 1;
assert builtins.length (ryokuOwnershipFailures hmShellConflict) == 1;
assert builtins.length (ryokuOwnershipFailures hmUserEditsAllowed) == 0;

assert lib.hasSuffix ".drv" defaults.system.build.toplevel.drvPath;
assert lib.hasSuffix ".drv" slim.system.build.toplevel.drvPath;
assert defaults.services.displayManager.sddm.enable;
assert defaults.services.displayManager.sddm.wayland.enable;
assert !(evaluate { services.displayManager.sddm.enable = false; }).services.displayManager.sddm.enable;
assert !(evaluate { services.greetd.enable = true; }).services.displayManager.sddm.enable;
assert (evaluate {
  programs.ryoku.defaultCompositor = "niri";
  services.displayManager.defaultSession = "hyprland";
}).services.displayManager.defaultSession == "hyprland";
assert defaults.virtualisation.docker.enable;
assert !defaults.services.flatpak.enable;
assert builtins.elem "fastfetch" defaultNames;
assert builtins.elem "gamescope" defaultNames;
assert builtins.elem "quickemu" defaultNames;
assert builtins.elem "skwd-paper" defaultNames;
assert builtins.elem "skwd-paper" ryogamiPathNames;

assert !slim.virtualisation.docker.enable;
assert slim.services.flatpak.enable;
assert builtins.elem "starship" slimNames;
assert builtins.elem "go" slimNames;
assert builtins.elem "firefox" slimNames;
assert !builtins.elem "fastfetch" slimNames;
assert !builtins.elem "gamescope" slimNames;
assert !builtins.elem "quickemu" slimNames;
assert slim.services.displayManager.defaultSession == "ryoku-niri";
assert slim.environment.sessionVariables.RYOKU_DEFAULT_BROWSER == "firefox";
assert slim.security.wrappers."gsr-kms-server".capabilities == "cap_sys_admin+ep";

assert plasmaCoexist.services.desktopManager.plasma6.enable;
assert plasmaCoexist.services.displayManager.sddm.enable;
assert plasmaCoexist.services.displayManager.defaultSession == "plasma";
assert builtins.elem "ryoku-niri-session" plasmaSessionNames;
assert builtins.any (name: lib.hasPrefix "plasma-workspace" name) plasmaSessionNames;

assert slimManifest.schema == 1;
assert slimManifest.host == "ryoku-installer-test";
assert slimManifest.shell == "zsh";
assert slimManifest.browser == "firefox";
assert slimManifest.defaultCompositor == "niri";
assert slimManifest.optionalApps == [ "prompt" "flatpak" "go" ];
assert lib.hasPrefix "/nix/store/" slimManifest.configBase;
assert lib.hasPrefix "/nix/store/" slimManifest.i18nDir;
assert builtins.length slimManifest.packages > 0;
assert builtins.all (p: lib.hasPrefix "/nix/store/" p.path) slimManifest.packages;

pkgs.runCommand "ryoku-installer-options-check" { } ''
  touch "$out"
''
