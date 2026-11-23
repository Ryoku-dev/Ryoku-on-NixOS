{ pkgs, self }:
let
  # A path: checkout may contain the previous result link. Do not embed an old
  # ISO (or the Git database) into the source carried by the next image.
  source = pkgs.lib.cleanSourceWith {
    src = self;
    filter = path: type:
      let name = baseNameOf path;
      in name != ".git" && !(type == "symlink" && pkgs.lib.hasPrefix "result" name);
  };
in
pkgs.writeShellApplication {
  name = "build-iso-offline";
  runtimeInputs = with pkgs; [ coreutils nixVersions.latest python3 ];
  text = ''
    export RYOKU_OFFLINE_FLAKE=path:${source}
    ${builtins.readFile ./build.sh}
  '';
}
