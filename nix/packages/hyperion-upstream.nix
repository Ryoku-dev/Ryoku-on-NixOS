# The pinned Hyperion package attrset, imported with the same arguments as
# the ryokuHyperion input's own flake.nix. Its flake exports only a few
# packages, and the full bundle cannot be split. Importing the attrset lets
# NixOS compose the individual components without rebuilding them or drifting
# from upstream. The ryoku-hyperion-bundle-provenance check checks that these
# derivations are identical to the flake's own outputs.
{ ryokuHyperion, pkgs, system }:

let
  inherit (pkgs) lib;
  inherit (ryokuHyperion) inputs;

  root = ryokuHyperion.outPath;

  version = builtins.replaceStrings [ "\n" "\r" ] [ "" "" ]
    (builtins.readFile (root + "/VERSION"));

  # Mirrors upstream's ryokuSource: same name and same filter, so the
  # filtered source and every derivation built from it match upstream.
  src = builtins.path {
    name = "ryoku-upstream-source";
    path = root;

    filter = path: type:
      let
        relative = lib.removePrefix "${toString root}/" (toString path);
      in
        !(relative == "nix"
          || lib.hasPrefix "nix/" relative
          || builtins.elem relative [ "flake.nix" "flake.lock" ]);
  };
in
import (root + "/nix/packages") {
  inherit pkgs version src;
  inherit (inputs)
    hyprglassSrc
    bibataMaterialSrc
    imgbordersSrc
    ryomanagerSrc
    ryotunesSrc
    ;
  skwdPaper = inputs.skwdWall.packages.${system}.skwd-paper;
  ryoportPackage = inputs.ryoport.packages.${system}.default;
}
