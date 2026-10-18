{ config, lib, ... }:

let
  version =
    builtins.replaceStrings
      [ "\n" "\r" ]
      [ "" "" ]
      (builtins.readFile ../../VERSION);

  codename =
    builtins.replaceStrings
      [ "\n" "\r" ]
      [ "" "" ]
      (builtins.readFile ../../CODENAME);

  # The sync records which Ryoku build this tree was taken from.
  upstream =
    if builtins.pathExists ../sync/upstream.json
    then (builtins.fromJSON (builtins.readFile ../sync/upstream.json)).upstream or { }
    else { };

in
{
  config = lib.mkIf config.programs.ryoku.enable {
    # Installed Ryoku release identity.
    #
    # Upstream packages publish this as /etc/ryoku-release. On NixOS the
    # system generation owns the same marker declaratively so `ryoku version
    # --pretty`, Hub and other release-aware surfaces identify the Nix port as
    # Musubi rather than inheriting the Arch release codename.
    environment.etc."ryoku-release".text = ''
      RELEASE="v${version}"
      NAME="${codename}"
      CHANNEL="nix"
      VERSION="${version}"
      COMMIT="${upstream.commit or ""}"
      DATE="${upstream.date or ""}"
    '';
  };
}
