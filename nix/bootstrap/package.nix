# Hyperion onboarding command.
#
# Evaluating this must stay cheap and independent of the desktop: it only
# needs the channel switcher and the update helper.
# It deliberately bundles no Nix, nixos-rebuild, systemd or gh. Channel
# switches run the host's own Nix, which matches the daemon and store the
# switch acts on, and nothing here needs a GitHub account.
{ pkgs }:

let
  nixUpdate = import ../packages/ryoku-nix-update.nix { inherit pkgs; };
  files = nixUpdate.files;
in
pkgs.writeShellApplication {
  name = "ryoku-v2";

  runtimeInputs = [
    pkgs.coreutils
    pkgs.diffutils
    pkgs.python3
    nixUpdate
  ];

  text = ''
    editor="${files}/scripts/ryoku-nix-track-edit.py"
    hyperion_source="github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos"

    require_nixos() {
      if [ ! -e /etc/NIXOS ]; then
        printf '%s\n' 'ryoku-v2: Hyperion for NixOS must be entered from a NixOS system.' >&2
        exit 1
      fi
      flake_root="''${RYOKU_NIX_FLAKE:-/etc/nixos}"
      if [ ! -f "$flake_root/flake.nix" ]; then
        printf 'ryoku-v2: no flake.nix in %s; Ryoku for NixOS manages flake-based systems.\n' "$flake_root" >&2
        exit 1
      fi
    }

    case "''${1:-}" in
      enter)
        require_nixos
        exec ryoku-nix-update track hyperion
        ;;
      slim)
        require_nixos
        export RYOKU_NIX_HYPERION_NIRI_ONLY=1
        exec ryoku-nix-update track hyperion
        ;;
      leave)
        require_nixos
        exec ryoku-nix-update track unstable
        ;;
      status)
        exec ryoku-nix-update status
        ;;
      plan)
        require_nixos
        temp="$(mktemp -d)"
        trap 'rm -rf "$temp"' EXIT
        cp "$flake_root/flake.nix" "$temp/flake.nix"
        module_args=()
        if [ -f "$flake_root/ryoku.nix" ]; then
          cp "$flake_root/ryoku.nix" "$temp/ryoku.nix"
          module_args=("$temp/ryoku.nix")
        fi
        RYOKU_NIX_HOST="$(hostname)" python3 "$editor" "$temp/flake.nix" "$hyperion_source" "''${module_args[@]}"
        diff -u "$flake_root/flake.nix" "$temp/flake.nix" || [ "$?" -eq 1 ]
        if [ "''${#module_args[@]}" -gt 0 ]; then
          diff -u "$flake_root/ryoku.nix" "$temp/ryoku.nix" || [ "$?" -eq 1 ]
        fi
        ;;
      *)
        printf '%s\n' \
          'Usage: ryoku-v2 COMMAND' \
          "" \
          '  plan       show the /etc/nixos changes enter would make' \
          '  enter      switch this NixOS system to Hyperion' \
          '  slim       switch to Hyperion with the Niri-only desktop' \
          '  leave      switch back to the unstable channel' \
          '  status     show the tracked channel' >&2
        exit 2
        ;;
    esac
  '';
}
