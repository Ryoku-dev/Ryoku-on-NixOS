{ pkgs, module }:
let
  # A minimally bootable synthetic NixOS host. Returning its full toplevel
  # below forces NixOS' real module assertions, including SDDM's backend
  # requirement, instead of merely inspecting option values.
  hostBaseline = {
    system.stateVersion = "26.05";

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
      hostBaseline
      { programs.ryoku.enable = true; }
      extra
    ];
  }).config;

  bare = evaluate { };

  disabled = evaluate {
    services.displayManager.sddm.enable = false;
  };

  custom = evaluate {
    services.displayManager.sddm.theme = "custom";
  };

  gdm = evaluate {
    services.displayManager.gdm.enable = true;
  };

  lightdm = evaluate {
    services.xserver.displayManager.lightdm.enable = true;
  };

  greetd = evaluate {
    services.greetd.enable = true;
  };

  mangoDefault = evaluate {
    programs.ryoku.defaultCompositor = "mango";
  };

  userDefault = evaluate {
    programs.ryoku.defaultCompositor = "mango";
    services.displayManager.defaultSession = "niri";
  };

  firefoxBrowser = evaluate {
    programs.ryoku.browser = "firefox";
  };
in

# No Desktop installs have no Xserver. Ryoku's fallback SDDM must therefore
# supply its Wayland backend or NixOS rejects system.build.toplevel.
assert !bare.services.xserver.enable;
assert bare.services.displayManager.sddm.enable;
assert bare.services.displayManager.sddm.wayland.enable;
assert bare.services.displayManager.sddm.theme == "ryoku";

# Preserve explicit user choices and existing display managers.
assert !disabled.services.displayManager.sddm.enable;
assert custom.services.displayManager.sddm.theme == "custom";
assert !gdm.services.displayManager.sddm.enable;
assert !lightdm.services.displayManager.sddm.enable;
assert !greetd.services.displayManager.sddm.enable;

# The installer-selected compositor beats provider defaults, while an explicit
# host choice still beats the installer preference.
assert mangoDefault.services.displayManager.defaultSession == "ryoku-mango";
assert userDefault.services.displayManager.defaultSession == "niri";

# Browser selection is declarative and reaches both PATH and the shell fallback.
assert builtins.elem pkgs.firefox firefoxBrowser.environment.systemPackages;
assert firefoxBrowser.environment.sessionVariables.RYOKU_DEFAULT_BROWSER == "firefox";

# This is deliberately the real system closure, not a dummy runCommand.
# Building this check forces NixOS' complete assertion machinery.
bare.system.build.toplevel
