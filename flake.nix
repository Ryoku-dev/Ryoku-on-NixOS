{
  description = "Nix packaging for the Ryoku desktop";

  inputs = {
    # Compatibility input for existing consumers which follow their host
    # nixpkgs. Ryoku-owned packages deliberately do not build from this input.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Fixed package universe for Ryoku itself. Keeping this independent of the
    # host prevents fetchPnpmDeps and other fixed-output builders from changing
    # underneath a Ryoku release when the host updates nixos-unstable.
    ryokuPackagesNixpkgs.url =
      "github:NixOS/nixpkgs/56c02bc00adcf003215cc4bd996d6efaf4cff188";

    glazepkg = {
      url = "github:neur0map/glazepkg";
      inputs.nixpkgs.follows = "ryokuPackagesNixpkgs";
    };

    hermesAgent = {
      url = "github:NousResearch/hermes-agent";
    };

    hyprglassSrc = {
      url = "github:hyprnux/hyprglass/v0.7.0";
      flake = false;
    };

    bibataMaterialSrc = {
      url = "github:rtgiskard/bibata_cursor/f4ccfe8abb63fddc7b3ce51a866fd8378395cb3d";
      flake = false;
    };

    imgbordersSrc = {
      url = "git+https://codeberg.org/zacoons/imgborders.git?ref=master";
      flake = false;
    };

    # Native Ryotunes 1.1.6, pinned to its release commit.
    # Keep this pinned to the exact upstream release commit.
    ryotunesSrc = {
      url = "github:Ryoku-dev/ryotunes/8fad27becd373ca7943b2e8943a8f14398b67ddb";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, ryokuPackagesNixpkgs, glazepkg, hermesAgent, hyprglassSrc, bibataMaterialSrc, imgbordersSrc, ryotunesSrc, ... }:
    let
      version =
        builtins.replaceStrings
          [ "\n" "\r" ]
          [ "" "" ]
          (builtins.readFile ./VERSION);

      system = "x86_64-linux";

      quickshellScreencopyFixOverlay = final: prev: {
        quickshell = prev.quickshell.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (prev.fetchurl {
          url = "https://github.com/quickshell-mirror/quickshell/commit/851ab0eac6bdfa9201a1a50e7bc3a6d29af25949.patch";
          hash = "sha256-g+8NQeFyGK9v76cPM9ogkMSfLH0SGPOyREFkTf6MJ7I=";
        })
          ];
        });
      };

      pkgs = import ryokuPackagesNixpkgs {
        inherit system;
        overlays = [
          quickshellScreencopyFixOverlay
        ];
      };

      ryoku = import ./nix/packages {
        inherit
          pkgs
          hyprglassSrc
          bibataMaterialSrc
          imgbordersSrc
          ryotunesSrc
          version
          ;

        src = self;
      };

      ryokuDev = import ./nix/apps/ryoku-dev.nix {
        inherit pkgs ryoku;
        src = self;
      };

      ryokuMaterialize = import ./nix/apps/ryoku-materialize.nix {
        inherit pkgs ryoku;
      };
      ryokuInstallBackend = import ./nix/apps/ryoku-install-backend.nix {
        inherit pkgs;
      };

      ryokuInstall = import ./nix/apps/ryoku-install.nix {
        inherit pkgs;
        backend = ryokuInstallBackend;
      };
    in
    {
      lib.version = version;

      nixosModules.default =
        import ./nix/modules/ryoku.nix {
          inherit self hermesAgent;
          ryokuNixpkgs = pkgs;
        };

      packages.${system} = {
        ryoku-install = ryokuInstall;
        ryoku-install-backend = ryokuInstallBackend;
        ryoku-shell = ryoku.shell;
        ryoku-ui = ryoku.ui;
        ryoku-plugin-kit = ryoku.pluginKit;
        ryoku-framebars = ryoku.frameBars;
        ryoku-wm-hyprland-qml = ryoku.wmHyprlandQml;
        ryoku-blobs = ryoku.blobs;

        ryoku-qml = ryoku.qml;

        ryoku-cli = ryoku.cli;
        ryoku-nix-update = ryoku.nixUpdate;
        ryoku-hub = ryoku.hub;
        ryoku-palette-bridge = ryoku.paletteBridge;
        ryoku-rashin = ryoku.rashin;
        ryoku-ryostore = ryoku.ryostore;
        ryoku-ryomotion = ryoku.ryomotion;
        ryoku-ryovm-helpers = ryoku.ryovmHelpers;
        ryoku-livewall = ryoku.livewall;
        ryoku-ryogami = ryoku.ryogami;
        ryoku-ryotunes = ryoku.ryotunes;
        ryotunes-unwrapped = ryoku.ryotunesUnwrapped;
        ryoku-keysounds = ryoku.keysounds;
        ryoku-qmk-hid = ryoku.qmkHid;
        ryoku-waifu2x = ryoku.waifu2x;
        ryoku-helpers = ryoku.helpers;
        ryoku-nixos-system-bridge = ryoku.nixosSystemBridge;
        ryoku-desktop-data = ryoku.desktopData;
        ryoku-wm-hyprland = ryoku.wmHyprland;
        ryoku-wm-niri = ryoku.wmNiri;
        ryoku-xwayland-satellite = ryoku.xwaylandSatellite;

        # Ryoku owns its compositor ABI. These come from Ryoku's
        # locked nixpkgs rather than the host's package set.
        ryoku-hyprland = pkgs.hyprland;
        ryoku-xdg-desktop-portal-hyprland = pkgs.xdg-desktop-portal-hyprland;
        ryoku-matugen = pkgs.matugen;

        ryoku-hyprglass = ryoku.hyprglass;
        ryoku-imgborders = ryoku.imgborders;
        ryoku-hypr-plugins = ryoku.hyprPlugins;
        ryoku-cursor-material = ryoku.cursorMaterial;
        ryoku-maple-mono-nf = ryoku.mapleMonoNF;

        ryoku-bundle = ryoku.bundle;

        ryoku-dev = ryokuDev;
        ryoku-materialize = ryokuMaterialize;
        gpk = glazepkg.packages.${system}.gpk;

        default = ryoku.bundle;
      };

      apps.${system} = {
        install = {
          type = "app";
          program = "${ryokuInstall}/bin/ryoku-install";
          meta.description = "Install Ryoku on an existing flake-based NixOS system";
        };

        ryoku-dev = {
          type = "app";
          program = "${ryokuDev}/bin/ryoku-dev";
          meta.description = "Run Ryoku directly from a development checkout";
        };

        ryoku-materialize = {
          type = "app";
          program = "${ryokuMaterialize}/bin/ryoku-materialize";
          meta.description = "Materialize the packaged Ryoku desktop into the user configuration";
        };

        default = {
          type = "app";
          program = "${ryokuDev}/bin/ryoku-dev";
          meta.description = "Run the Ryoku development environment";
        };
      };

      checks.${system} = {
        ryoku-installer-options = import ./nix/tests/installer-options.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };

        ryoku-installer-transaction = pkgs.runCommand "ryoku-installer-transaction-check"
          { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            RYOKU_INSTALL_TEST_BACKEND=${ryokuInstallBackend}/bin/ryoku-install-backend \
              python3 ${./nix/tests/test-installer-transaction.py}
            touch "$out"
          '';

        ryoku-installer-cache-option = pkgs.runCommand "ryoku-installer-cache-option-check"
          { nativeBuildInputs = [ pkgs.gnugrep ]; }
          ''
            backend=${ryokuInstallBackend}/bin/ryoku-install-backend
            "$backend" --help | grep -Fq -- '--no-cache'
            grep -Fq 'binaryCache.enable = $([ "$use_cache" -eq 1 ] && printf true || printf false);' ${./nix/apps/ryoku-install-backend.nix}
            touch "$out"
          '';

        ryoku-installer-wrapper = import ./nix/tests/installer-wrapper.nix {
          inherit pkgs;
          installer = ryokuInstall;
        };

        ryoku-materializer-unit-cleanup = pkgs.runCommand
          "ryoku-materializer-unit-cleanup-check"
          { nativeBuildInputs = [ pkgs.gnugrep ]; }
          ''
            materializer=${./nix/apps/ryoku-materialize.nix}
            grep -Fq 'ryogami.service' "$materializer"
            grep -Fq 'ryoku-session.target.wants/ryogami.service' "$materializer"
            touch "$out"
          '';


        ryoku-session-bootstrap = pkgs.runCommand "ryoku-session-bootstrap-check"
          { nativeBuildInputs = [ pkgs.gnugrep ]; }
          ''
            hypr=${ryoku.desktopData}/share/ryoku/config/hypr/modules/autostart.lua
            niri=${ryoku.desktopData}/share/ryoku/config/niri/autostart.kdl

            grep -Fq 'ryoku-nix-session-start' "$hypr"
            grep -Fq 'ryoku-nix-session-start' "$niri"
            ! grep -Fq 'dbus-update-activation-environment --systemd --all; systemctl --user daemon-reload' "$hypr"
            ! grep -Fq 'dbus-update-activation-environment --systemd --all; systemctl --user daemon-reload' "$niri"

            touch "$out"
          '';

        # Core runtime
        ryoku-shell = ryoku.shell;
        ryoku-cli = ryoku.cli;
        ryoku-hub = ryoku.hub;
        ryoku-palette-bridge = ryoku.paletteBridge;
        ryoku-rashin = ryoku.rashin;
        ryoku-ryostore = ryoku.ryostore;
        ryoku-ryomotion = ryoku.ryomotion;
        ryoku-ryovm-helpers = ryoku.ryovmHelpers;
        ryoku-livewall = ryoku.livewall;
        ryoku-ryogami = ryoku.ryogami;
        ryoku-ryotunes = ryoku.ryotunes;
        ryoku-keysounds = ryoku.keysounds;
        ryoku-qmk-hid = ryoku.qmkHid;
        ryoku-waifu2x = ryoku.waifu2x;

        ryoku-waifu2x-models = pkgs.runCommand
          "ryoku-waifu2x-models-check"
          { }
          ''
            test -d               "${ryoku.waifu2x}/share/waifu2x-ncnn-vulkan/models-cunet"

            test -n "$(
              find                 "${ryoku.waifu2x}/share/waifu2x-ncnn-vulkan/models-cunet"                 -maxdepth 1                 -type f                 -print                 -quit
            )"

            touch "$out"
          '';

        # QML modules
        ryoku-ui = ryoku.ui;
        ryoku-plugin-kit = ryoku.pluginKit;
        ryoku-framebars = ryoku.frameBars;
        ryoku-wm-hyprland-qml = ryoku.wmHyprlandQml;
        ryoku-blobs = ryoku.blobs;
        ryoku-qml = ryoku.qml;

        # Desktop integration
        ryoku-desktop-data = ryoku.desktopData;
        ryoku-wm-hyprland = ryoku.wmHyprland;
        ryoku-wm-niri = ryoku.wmNiri;
        ryoku-xwayland-satellite = ryoku.xwaylandSatellite;
        ryoku-helpers = ryoku.helpers;
        ryoku-nixos-system-bridge = ryoku.nixosSystemBridge;
        ryoku-bundle = ryoku.bundle;

        # GPU/MUX policy
        #
        # These are upstream's hermetic hardware-policy regressions. They use
        # synthetic DRM/sysfs trees and never touch the host GPU or firmware.
        ryoku-gpu-mux-policy = pkgs.runCommand
          "ryoku-gpu-mux-policy-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              gnugrep
              gnused
              jq
              pciutils
              procps
            ];
          }
          ''
            bash ${self}/tests/gpu-mux.sh
            touch "$out"
          '';

        ryoku-gpu-pin-policy = pkgs.runCommand
          "ryoku-gpu-pin-policy-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              gnugrep
              gnused
              jq
              pciutils
              procps
            ];
          }
          ''
            bash ${self}/tests/gpu-pin-policy.sh
            touch "$out"
          '';

        # Nix update helper serialization
        ryoku-nix-update-lock = pkgs.runCommand
          "ryoku-nix-update-lock-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gnugrep
              util-linux
            ];
          }
          ''
            RYOKU_NIX_UPDATE_TEST_HELPER=${./nix/scripts/ryoku-nix-update} \
              bash ${./nix/tests/test-nix-update-lock.sh}
            touch "$out"
          '';

        ryoku-nix-update-local-rollback = pkgs.runCommand
          "ryoku-nix-update-local-rollback-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              git
              jq
              util-linux
            ];
          }
          ''
            RYOKU_NIX_UPDATE_TEST_HELPER=${./nix/scripts/ryoku-nix-update} \
              bash ${./nix/tests/test-nix-update-local-rollback.sh}
            touch "$out"
          '';

        # Nix update failed-activation rollback
        ryoku-nix-update-activation-rollback = pkgs.runCommand
          "ryoku-nix-update-activation-rollback-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              git
              gnugrep
              jq
              util-linux
            ];
          }
          ''
            RYOKU_NIX_UPDATE_TEST_HELPER=${./nix/scripts/ryoku-nix-update} \
              bash ${./nix/tests/test-nix-update-activation-rollback.sh}
            touch "$out"
          '';

        ryoku-nix-update-refresh = pkgs.runCommand
          "ryoku-nix-update-refresh-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              gnugrep
            ];
          }
          ''
            RYOKU_NIX_UPDATE_TEST_HELPER=${./nix/scripts/ryoku-nix-update} \
              bash ${./nix/tests/test-nix-update-refresh.sh}
            touch "$out"
          '';

        # CLI integration
        ryoku-cli-config-base = pkgs.runCommand
          "ryoku-cli-config-base-check"
          { }
          ''
            output="$(${ryoku.cli}/bin/ryoku status)"

            printf '%s\n' "$output" |
              ${pkgs.gnugrep}/bin/grep -Fq \
                "config base:   ${ryoku.desktopData}/share/ryoku/config"

            touch "$out"
          '';

        # Installer
        ryoku-install = ryokuInstall;
        ryoku-install-backend = ryokuInstallBackend;

        ryoku-install-parser = pkgs.runCommand
          "ryoku-install-parser-check"
          {
            nativeBuildInputs = [
              pkgs.python3
              pkgs.nix
            ];
          }
          ''
            # nix-instantiate --parse still initialises Nix's state directory.
            # Builds cannot write /nix/var/nix, so keep the parser check's
            # otherwise-unused state inside the writable build directory.
            export NIX_STATE_DIR="$TMPDIR/nix-state"
            export NIX_LOG_DIR="$TMPDIR/nix-log"
            mkdir -p "$NIX_STATE_DIR" "$NIX_LOG_DIR"

            RYOKU_INSTALL_PARSER=${./nix/apps/ryoku-install-edit.py} \
              python3 ${./nix/tests/test-ryoku-install-edit.py}

            touch "$out"
          '';

        # User-facing deployment utility
        ryoku-materialize = ryokuMaterialize;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          go
          cmake
          ninja
          pkg-config

          qt6.qtbase
          qt6.qtdeclarative
          qt6.qtmultimedia
          qt6.qtshadertools

          quickshell
        ];

        shellHook = ''
          export GOTOOLCHAIN=local
        '';
      };
    };
}
