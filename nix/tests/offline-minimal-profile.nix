{ pkgs, configurations, buildTools }:
let
  verify = machine:
    let c = machine.config; names = map pkgs.lib.getName c.environment.systemPackages;
    in assert c.programs.ryoku.minimal;
       assert c.programs.ryoku.defaultCompositor == "niri";
       assert c.programs.ryoku.browser == "firefox";
       assert c.programs.ryoku.optionalApps == [ ];
       assert !c.programs.hyprland.enable;
       assert c.programs.niri.enable;
       assert c.boot.kernelPackages.kernel.version == machine.pkgs.linuxPackages_latest.kernel.version;
       assert c.fileSystems."/".fsType == "ext4";
       assert builtins.elem "firefox" names;
       assert !(builtins.elem "chromium" names);
       assert !(builtins.elem "ryoku-desktop-bundle" names);
       assert !(builtins.elem "ryoku-wm-hyprland" names);
       assert !(builtins.elem "ryoku-wm-mango" names);
       true;
  verifyTools = machine:
    let p = machine.pkgs;
    in builtins.all (tool: builtins.elem (toString tool) (map toString buildTools)) [
      p.libcap-text-verifier p.libxslt.bin p.lndir p.texinfo
      p.coreutils-full p.coreutils-full.info
      (p.lib.getBin p.kmod) p.kmod.dev p.kmod.man
    ];
in
assert builtins.all verifyTools (builtins.attrValues configurations);
assert builtins.all (name: builtins.elem name (map pkgs.lib.getName buildTools))
  [ "libcap-text-verifier" "libxslt" "lndir" "coreutils-full" "kmod" "texinfo" ];
assert builtins.all verify (builtins.attrValues configurations);
pkgs.runCommand "offline-minimal-profile-check" { } ''touch "$out"''
