{ pkgs, installer }:

pkgs.runCommand "ryoku-installer-wrapper-check"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    fixture="$TMPDIR/nixos"
    mkdir -p "$fixture"

    cat > "$fixture/flake.nix" <<'FLAKE'
    {
      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

      outputs = { self, nixpkgs, ... }: {
        nixosConfigurations.host = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ ./configuration.nix ];
        };
      };
    }
FLAKE

    cat > "$fixture/configuration.nix" <<'NIX'
    { ... }: {
      system.stateVersion = "26.05";
    }
NIX

    output="$(${installer}/bin/ryoku-install \
      --cli \
      --flake "$fixture#host" \
      --source github:aethctl/Ryoku-on-NixOS/main \
      --compositor niri \
      --browser firefox \
      --shell zsh \
      --apps prompt,flatpak,go \
      --dry-run \
      -y)"

    printf '%s\n' "$output" | grep -Fq 'WM      niri'
    printf '%s\n' "$output" | grep -Fq 'Browser firefox'
    printf '%s\n' "$output" | grep -Fq 'Shell   zsh'
    printf '%s\n' "$output" | grep -Fq 'Apps    prompt,flatpak,go'
    printf '%s\n' "$output" | grep -Fq 'defaultCompositor = "niri";'
    printf '%s\n' "$output" | grep -Fq 'browser = "firefox";'
    printf '%s\n' "$output" | grep -Fq 'shell = "zsh";'
    printf '%s\n' "$output" | grep -Fq '"flatpak"'
    printf '%s\n' "$output" | grep -Fq 'Dry run complete. No files were changed.'

    test ! -e "$fixture/ryoku.nix"
    grep -Fq './configuration.nix' "$fixture/flake.nix"
    ! grep -Fq 'ryoku.nixosModules.default' "$fixture/flake.nix"

    touch "$out"
  ''
