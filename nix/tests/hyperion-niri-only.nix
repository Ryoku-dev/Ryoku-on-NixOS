{ pkgs, module, hyperionPackages, ryokuPackages }:
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

  # Reference checks: compare store paths, not package names.
  hasPkg = list: p: lib.elem p.outPath (map (x: x.outPath) list);
  ryogamiUnit = config: config.systemd.user.services.ryogami;
  integration = config: builtins.fromJSON (builtins.unsafeDiscardStringContext
    config.environment.etc."ryoku/nix-integration.json".text);

  desktopData = hyperionPackages.ryoku-desktop-data;
  ryogami = hyperionPackages.ryoku-ryogami;

  # Hyperion's Ryogami and desktop data, not the legacy NixOS builds.
  usesHyperionData = config:
    (ryogamiUnit config).serviceConfig.ExecStart == "${ryogami}/bin/ryogami"
    && lib.hasPrefix "${ryogami}/lib/qt-6/qml:" (ryogamiUnit config).environment.QML_IMPORT_PATH
    && config.environment.sessionVariables.RYOKU_I18N_DIR == "${desktopData}/share/ryoku/i18n"
    && (shellEnv config).RYOKU_QYLOCK_BUNDLE == "${desktopData}/share/ryoku/lockscreen/qylock"
    && (integration config).configBase == "${desktopData}/share/ryoku/config";
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
assert hyperion.xdg.portal.config.hyprland.default == "hyprland;gtk";

# Niri-only removes Hyprland packages, portal, plugins and sessions.
assert !niriOnly.programs.hyprland.enable;
assert !hasHyprName niriOnly.services.displayManager.sessionPackages;
assert !hasHyprlandName niriOnly.environment.systemPackages;
assert !hasHyprlandName niriOnly.systemd.user.services.ryoku-shell.path;
assert !hasHyprName niriOnly.xdg.portal.extraPortals;
assert !(niriOnly.xdg.portal.config ? hyprland);
assert !(niriOnly.environment.etc ? "xdg/xdg-desktop-portal/hyprland-portals.conf");
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

# Each mode installs its own bundle and not the other.
assert hasPkg hyperion.environment.systemPackages ryokuPackages.ryoku-hyperion-nixos-bundle;
assert !(hasPkg hyperion.environment.systemPackages ryokuPackages.ryoku-hyperion-niri-nixos-bundle);
assert hasPkg niriOnly.environment.systemPackages ryokuPackages.ryoku-hyperion-niri-nixos-bundle;
assert !(hasPkg niriOnly.environment.systemPackages ryokuPackages.ryoku-hyperion-nixos-bundle);
assert hasPkg niriOnly.systemd.user.services.ryoku-shell.path ryokuPackages.ryoku-hyperion-niri-nixos-bundle;

# No Hyprland provider or plugins reach the Niri-only system, by store path.
assert lib.all (p: !(hasPkg niriOnly.environment.systemPackages p)) [
  hyperionPackages.ryoku-wm-hyprland
  ryokuPackages.ryoku-wm-hyprland
  ryokuPackages.ryoku-hypr-plugins
  ryokuPackages.ryoku-hyprland
];

# Both Hyperion modes use Hyperion's Ryogami and desktop data.
assert usesHyperionData hyperion;
assert usesHyperionData niriOnly;

pkgs.writeText "ryoku-hyperion-niri-only-check" "ok\n"
