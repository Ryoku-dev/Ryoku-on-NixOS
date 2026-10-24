# AMD graphics defaults for Ryoku on NixOS.
{ ... }:

{
  # Mesa and RADV are supplied by hardware.graphics. Loading amdgpu in the
  # initrd gives Wayland early KMS without replacing NixOS's normal driver
  # selection.
  boot.initrd.kernelModules = [ "amdgpu" ];
}
