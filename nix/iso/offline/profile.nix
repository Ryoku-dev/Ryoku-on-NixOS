# Shared contract for the payload and the configuration installed from it.
{ lib, ... }:
{
  programs.ryoku = {
    minimal = true;
    defaultCompositor = lib.mkForce "niri";
    browser = lib.mkForce "firefox";
    shell = lib.mkForce "fish";
    optionalApps = lib.mkForce [ ];
  };
}
