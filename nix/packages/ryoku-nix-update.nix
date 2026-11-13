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
    procps
    python3
    systemd
    util-linux
  ];

  text = ''
    # Retain only the standalone editor, not the entire repository, at runtime.
    export RYOKU_NIX_FLAKE_EDITOR="${builtins.path {
      path = src + "/nix/scripts/ryoku-nix-track-edit.py";
      name = "ryoku-nix-track-edit.py";
    }}"
    ${builtins.readFile (src + "/nix/scripts/ryoku-nix-update")}
  '';
}
