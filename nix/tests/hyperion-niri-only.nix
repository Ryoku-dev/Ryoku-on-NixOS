{ pkgs, module }:
let
  inherit (pkgs) lib;

  hostPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  evaluate = extra: import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = pkgs.stdenv.hostPlatform.system;

    modules = [
      module
      {
        system.stateVersion = "26.05";
        nixpkgs.pkgs = hostPkgs;
        nixpkgs.config = lib.mkForce { };
        fileSystems."/" = {
          device = "none";
          fsType = "tmpfs";
        };
        boot.loader.grub = {
          enable = true;
          devices = [ "/dev/vda" ];
        };
        programs.ryoku.enable = true;
      }
      extra
    ];
  };

  failedAssertions = config:
    map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);

  names = map lib.getName;
  hasHyprName = list: lib.any (lib.hasInfix "hypr") (map lib.toLower (names list));
  hasHyprlandName = list: lib.any (n: lib.hasInfix "hyprland" (lib.toLower n) || lib.hasInfix "hypr-plugins" n) (names list);

  hyperion = (evaluate {
    programs.ryoku.hyperionPackages.enable = true;
  }).config;

  niriOnly = (evaluate {
    programs.ryoku.hyperionPackages.enable = true;
    programs.ryoku.hyperionNiriOnly.enable = true;
    programs.ryoku.defaultCompositor = "niri";
  }).config;

  withoutHyperion = (evaluate {
    programs.ryoku.hyperionNiriOnly.enable = true;
  }).config;

  hyprlandDefault = (evaluate {
    programs.ryoku.hyperionPackages.enable = true;
    programs.ryoku.hyperionNiriOnly.enable = true;
    programs.ryoku.defaultCompositor = "hyprland";
  }).config;

  shellEnv = config: config.systemd.user.services.ryoku-shell.environment;
in

assert failedAssertions hyperion == [ ];
assert failedAssertions niriOnly == [ ];
assert lib.any (lib.hasInfix "requires programs.ryoku.hyperionPackages.enable")
  (failedAssertions withoutHyperion);
assert lib.any (lib.hasInfix "cannot use Hyprland")
  (failedAssertions hyprlandDefault);

# The regular Hyperion preview keeps both compositors.
assert hyperion.programs.hyprland.enable;
assert hasHyprlandName hyperion.services.displayManager.sessionPackages;
assert hyperion.environment.sessionVariables ? RYOKU_HYPR_PLUGIN_DIR;

# Niri-only removes Hyprland packages, portal, plugins and sessions.
assert !niriOnly.programs.hyprland.enable;
assert !hasHyprName niriOnly.services.displayManager.sessionPackages;
assert !hasHyprlandName niriOnly.environment.systemPackages;
assert !hasHyprlandName niriOnly.systemd.user.services.ryoku-shell.path;
assert !hasHyprName niriOnly.xdg.portal.extraPortals;
assert !(niriOnly.environment.sessionVariables ? RYOKU_HYPR_PLUGIN_DIR);
assert !(shellEnv niriOnly ? RYOKU_HYPR_PLUGIN_DIR);

# The Niri desktop, Xwayland, SDDM and the Hyperion QML runtime remain.
assert niriOnly.programs.niri.enable;
assert lib.elem "ryoku-niri-session" (names niriOnly.services.displayManager.sessionPackages);
assert niriOnly.services.displayManager.defaultSession == "ryoku-niri";
assert niriOnly.programs.xwayland.enable;
assert niriOnly.security.polkit.enable;
assert niriOnly.services.displayManager.sddm.enable;
assert niriOnly.systemd.user.services ? ryoku-shell;
assert (shellEnv niriOnly).QML_IMPORT_PATH == (shellEnv hyperion).QML_IMPORT_PATH;
assert lib.elem "ryoku-wm-niri" (names niriOnly.environment.systemPackages);

pkgs.writeText "ryoku-hyperion-niri-only-check" "ok\n"
