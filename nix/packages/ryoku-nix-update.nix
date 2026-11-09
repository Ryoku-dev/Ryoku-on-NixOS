{ pkgs, src }:

pkgs.writeShellApplication {
  name = "ryoku-nix-update";

  runtimeInputs = with pkgs; [
    coreutils
    curl
    git
    gnugrep
    gnused
    jq
    nix
    nixos-rebuild
    openssl
    procps
    python3
    systemd
    util-linux
  ];

  text = ''
    export RYOKU_NIX_FLAKE_EDITOR="${src}/nix/scripts/ryoku-nix-track-edit.py"
    export RYOKU_HYPERION_INVITE_VERIFIER="${src}/nix/scripts/ryoku-hyperion-invite.py"
    ${builtins.readFile (src + "/nix/scripts/ryoku-nix-update")}
  '';
}
