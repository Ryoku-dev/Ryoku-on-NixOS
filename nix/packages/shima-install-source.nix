{ pkgs, src }:
let
  lock = builtins.fromJSON (builtins.readFile (src + "/flake.lock"));
  nodes = lock.nodes;
  runtimeNixpkgs = nodes.ryokuPackagesNixpkgs;
  runtimeLock = {
    version = 7;
    root = "root";
    nodes = {
      root.inputs = { nixpkgs = "nixpkgs"; inirSrc = "inirSrc"; };
      nixpkgs = runtimeNixpkgs // { original = { inherit (runtimeNixpkgs.locked) owner repo rev type; }; };
      inirSrc = nodes.inirSrc;
    };
  };
  definition = ''
    {
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/${runtimeNixpkgs.locked.rev}";
      inputs.inirSrc = {
        url = "github:snowarch/iNiR/${nodes.inirSrc.locked.rev}";
        flake = false;
      };
      outputs = { self, nixpkgs, inirSrc }:
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ (import ./quickshell-screencopy-overlay.nix) ];
          };
        in {
          packages.x86_64-linux.default = import ./ryoku-shima.nix {
            inherit pkgs;
            src = inirSrc;
          };
        };
    }
  '';
in pkgs.runCommand "ryoku-shima-install-source" {} ''
  mkdir -p "$out/shima"
  cp ${src}/nix/packages/ryoku-shima.nix "$out/ryoku-shima.nix"
  cp ${src}/nix/packages/quickshell-screencopy-overlay.nix "$out/quickshell-screencopy-overlay.nix"
  cp ${src}/nix/packages/shima/*.py ${src}/nix/packages/shima/*.qml ${src}/nix/packages/shima/NOTICE "$out/shima/"
  cp ${pkgs.writeText "flake.nix" definition} "$out/flake.nix"
  cp ${pkgs.writeText "flake.lock" (builtins.toJSON runtimeLock)} "$out/flake.lock"
''
