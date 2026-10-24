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

  # nix/sync/ryoku-sync writes the upstream Ryoku commit this tree is
  # synced to, so the marker names the exact upstream build.
  ryokuCommit =
    builtins.replaceStrings
      [ "\n" "\r" ]
      [ "" "" ]
      (builtins.readFile ../sync/ryoku-commit);

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
      COMMIT="${ryokuCommit}"
      DATE=""
    '';
  };
}
