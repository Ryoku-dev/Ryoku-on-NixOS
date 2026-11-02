{ pkgs, src }:
let
  lock = builtins.fromJSON (builtins.readFile (src + "/flake.lock"));
  nodes = lock.nodes;
  runtimeLock = {
    version = 7;
    root = "root";
    nodes = {
      root.inputs = { nixpkgs = "nixpkgs"; inirSrc = "inirSrc"; };
      nixpkgs = nodes.nixpkgs // { original = { inherit (nodes.nixpkgs.locked) owner repo rev type; }; };
      inirSrc = nodes.inirSrc;
    };
  };
  definition = ''
    {
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/${nodes.nixpkgs.locked.rev}";
      inputs.inirSrc = {
        url = "github:snowarch/iNiR/${nodes.inirSrc.locked.rev}";
        flake = false;
      };
      outputs = { self, nixpkgs, inirSrc }: {
        packages.x86_64-linux.default = import ./ryoku-shima.nix {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          src = inirSrc;
        };
      };
    }
  '';
in pkgs.runCommand "ryoku-shima-install-source" {} ''
  mkdir -p "$out/shima"
  cp ${src}/nix/packages/ryoku-shima.nix "$out/ryoku-shima.nix"
  cp ${src}/nix/packages/shima/* "$out/shima/"
  cp ${pkgs.writeText "flake.nix" definition} "$out/flake.nix"
  cp ${pkgs.writeText "flake.lock" (builtins.toJSON runtimeLock)} "$out/flake.lock"
''
