# Managed defaults for Ryoku on NixOS.
# Desktop choices made by the installer live in install-values.nix.
{ install, ... }:

{
  programs.ryoku = {
    enable = true;
    binaryCache.enable = install.binaryCache;
    defaultCompositor = install.compositor;
    browser = install.browser;
    shell = install.shell;
    optionalApps = install.optionalApps;
    updateFlake = "/etc/nixos";
  };
}
