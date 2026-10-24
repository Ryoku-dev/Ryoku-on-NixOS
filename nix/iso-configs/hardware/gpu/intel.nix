# Intel graphics defaults for Ryoku on NixOS.
{ pkgs, ... }:

{
  boot.initrd.kernelModules = [ "i915" ];

  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
}
