{
  description = "Ryoku on NixOS";

  inputs = {
    # Keep normal moving branch URLs here. The installer writes a lock file
    # pinned to the exact revisions tested by the ISO, so future `nix flake
    # update` calls can advance normally instead of pinning users forever.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ryoku.url = "github:aethctl/Ryoku-on-NixOS/main";
  };

  outputs = { nixpkgs, ryoku, ... }@inputs:
    let
      install = import ./install-values.nix;
    in
    {
      nixosConfigurations.ryoku = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {
          inherit inputs install;
        };
        modules = [
          ryoku.nixosModules.default
          ./ryoku.nix
          ./configuration.nix
        ];
      };
    };
}
