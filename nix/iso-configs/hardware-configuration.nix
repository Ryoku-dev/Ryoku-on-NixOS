# Placeholder for repository evaluation.
# The Ryoku ISO installer replaces this entire file with the output of
# `nixos-generate-config --show-hardware-config` for the target machine.
{ ... }:

{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
