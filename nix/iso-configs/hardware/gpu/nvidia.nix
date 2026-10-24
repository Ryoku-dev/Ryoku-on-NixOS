# NVIDIA graphics defaults for Ryoku on NixOS.
{ install, lib, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;

    # The installer selects the driver generation from the detected GPU. This
    # matters now that current NVIDIA releases no longer support Maxwell,
    # Pascal, or Volta while modern GPUs prefer the open kernel modules.
    branch = lib.mkDefault install.nvidiaBranch;
    open = lib.mkDefault install.nvidiaOpen;

    nvidiaSettings = true;
  };
}
