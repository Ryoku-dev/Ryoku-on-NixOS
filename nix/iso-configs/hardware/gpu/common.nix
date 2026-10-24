# Shared graphics stack for every Ryoku installation.
{ ... }:

{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
