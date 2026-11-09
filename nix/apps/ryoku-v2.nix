{ pkgs, src, ryokuNixUpdate }:

pkgs.writeShellApplication {
  name = "ryoku-v2";

  runtimeInputs = with pkgs; [
    coreutils
    diffutils
    gh
    openssl
    python3
    ryokuNixUpdate
  ];

  text = ''
    case "''${1:-}" in
      authorize)
        exec python3 "${src}/nix/scripts/ryoku-hyperion-invite.py" authorize
        ;;
      enter)
        exec ryoku-nix-update track hyperion
        ;;
      slim)
        export RYOKU_NIX_HYPERION_NIRI_ONLY=1
        exec ryoku-nix-update track hyperion
        ;;
      leave)
        exec ryoku-nix-update track unstable
        ;;
      status)
        exec ryoku-nix-update status
        ;;
      plan)
        flake_root="''${RYOKU_NIX_FLAKE:-/etc/nixos}"
        [ -f "$flake_root/flake.nix" ] || {
          printf 'ryoku-v2: flake.nix not found in %s\n' "$flake_root" >&2
          exit 1
        }

        temp="$(mktemp -d)"
        trap 'rm -rf "$temp"' EXIT
        cp "$flake_root/flake.nix" "$temp/flake.nix"
        python3 "${src}/nix/scripts/ryoku-nix-track-edit.py" \
          "$temp/flake.nix" \
          "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos"
        diff -u "$flake_root/flake.nix" "$temp/flake.nix" || [ "$?" -eq 1 ]
        ;;
      *)
        printf '%s\n' 'Usage: ryoku-v2 {authorize|plan|enter|slim|leave|status}' >&2
        exit 2
        ;;
    esac
  '';
}
