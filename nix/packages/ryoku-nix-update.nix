{ pkgs, ... }:

let
  inherit (pkgs) lib;

  # The helper, its channel editor and the invitation verifier, laid out as in
  # nix/ so the verifier finds ../keys. Nothing else of the repository is
  # copied, which keeps ryoku-v2 independent of unrelated source changes.
  files = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../keys/hyperion-invite-public.pem
      ../scripts/ryoku-hyperion-invite.py
      ../scripts/ryoku-nix-track-edit.py
      ../scripts/ryoku-nix-update
    ];
  };
in
pkgs.writeShellApplication {
  name = "ryoku-nix-update";

  # nix, nixos-rebuild, systemctl and pkill come from the host (see the PATH
  # note in the script): they must match the running daemon, store and init.
  runtimeInputs = with pkgs; [
    coreutils
    curl
    diffutils
    git
    gnugrep
    gnused
    jq
    openssl
    python3
    util-linux
  ];

  passthru = { inherit files; };

  text = ''
    export RYOKU_NIX_FLAKE_EDITOR="${files}/scripts/ryoku-nix-track-edit.py"
    export RYOKU_HYPERION_INVITE_VERIFIER="${files}/scripts/ryoku-hyperion-invite.py"
    ${builtins.readFile ../scripts/ryoku-nix-update}
  '';
}
