{ ryokuInstall, ... }:

{
  imports = [
    ./base.nix
    ./profile.nix
  ];

  # Make the already-tested guided installer available in the live image for
  # development and recovery. A fresh-disk installer should use nixos-install
  # against /mnt rather than invoking this command as its final install step.
  environment.systemPackages = [
    ryokuInstall
  ];
}
