{
  description = "Ryoku Hyperion for NixOS onboarding (invitation and channel switch)";

  # One input, pinned to the package set the main Ryoku flake builds with, so
  # this evaluates to the same ryoku-v2 derivation as
  # github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos#ryoku-v2 without
  # evaluating the desktop, Hyperion or RyoMarket inputs.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/1c89083e451e891152365b799595cf7790a43325";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      ryokuV2 = import ./package.nix {
        pkgs = nixpkgs.legacyPackages.${system};
      };
    in
    {
      packages.${system} = {
        ryoku-v2 = ryokuV2;
        default = ryokuV2;
      };

      apps.${system} = rec {
        ryoku-v2 = {
          type = "app";
          program = "${ryokuV2}/bin/ryoku-v2";
          meta.description = "Authorize and enter Ryoku Hyperion on NixOS";
        };
        default = ryoku-v2;
      };
    };
}
