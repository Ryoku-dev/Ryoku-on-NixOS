{ pkgs, module }:
let
  evaluate = phone: (import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [ module {
      system.stateVersion = "26.05";
      programs.ryoku.enable = true;
      programs.ryoku.phone = phone;
    } ];
  }).config;
  disabled = evaluate { };
  enabled = evaluate { enable = true; };
  webcam = evaluate { enable = true; webcam.enable = true; };
in
assert !(builtins.fromJSON disabled.environment.etc."ryoku/phone.json".text).enabled;
assert (builtins.fromJSON enabled.environment.etc."ryoku/phone.json".text).enabled;
assert enabled.programs.kdeconnect.enable;
assert builtins.any (p: pkgs.lib.getName p == "android-tools") enabled.environment.systemPackages;
assert !(builtins.elem "v4l2loopback" enabled.boot.kernelModules);
assert builtins.elem "v4l2loopback" webcam.boot.kernelModules;
assert builtins.elem webcam.boot.kernelPackages.v4l2loopback webcam.boot.extraModulePackages;
assert (builtins.fromJSON webcam.environment.etc."ryoku/phone.json".text).webcam;
pkgs.runCommand "ryoku-phone-config-check" { } ''
  touch "$out"
''
