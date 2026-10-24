{
  description = "Nix packaging for the Ryoku desktop";

  inputs = {
    ryokuUpstream.url = "github:Ryoku-dev/ryoku/unstable-dev";

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

    skwdWall = {
      url = "github:liixini/skwd-wall/nix";
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

    # RyoManager task manager, pinned to the approved Ryoku UI build.
    ryomanagerSrc = {
      url = "github:Ryoku-dev/ryomanager/459c6714e31276f73025369e722cf4ab48eccbc3";
      flake = false;
    };

    # Native Ryotunes 1.2.0, pinned to its release commit.
    # Keep this pinned to the exact upstream release commit.
    ryotunesSrc = {
      url = "github:Ryoku-dev/ryotunes/ade86b744651b908f3946b6769853e5084a59ce1";
      flake = false;
    };
  };

  outputs = { self, ryokuUpstream, nixpkgs, ryokuPackagesNixpkgs, glazepkg, hermesAgent, skwdWall, hyprglassSrc, bibataMaterialSrc, imgbordersSrc, ryomanagerSrc, ryotunesSrc, ... }:
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

      skwdPaper = skwdWall.packages.${system}.skwd-paper;

      ryoku = import ./nix/packages {
        inherit
          pkgs
          hyprglassSrc
          bibataMaterialSrc
          imgbordersSrc
          ryomanagerSrc
          ryotunesSrc
          skwdPaper
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

      # Temporary composition test for the cross-repository migration.
      # The active NixOS module continues using the existing package set.
      ryokuUpstreamNixosBundle = pkgs.symlinkJoin {
        name = "ryoku-upstream-nixos-bundle";

        # The NixOS bridge must take precedence over upstream
        # helpers with the same executable names.
        paths = [
          ryoku.nixosSystemBridge
          ryoku.nixUpdate
          ryokuUpstream.packages.${system}.ryoku-desktop
        ];
      };

      ryokuNixosModule =
        import ./nix/modules/ryoku.nix {
          inherit self hermesAgent ryokuUpstream;
          ryokuNixpkgs = pkgs;
        };

      ryokuRepo = "github:Ryoku-dev/Ryoku-on-NixOS";

      # Bootable Ryoku-on-NixOS live/install image. The live environment tracks
      # the flake's nixos-unstable input; Ryoku-owned packages remain pinned to
      # Ryoku's separate package universe. Both are locked by flake.lock.
      # `channel` is the branch installed systems follow afterwards.
      mkRyokuIso = channel: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit self ryokuInstall ryokuRepo;
          ryokuIsoChannel = channel;
          ryokuIsoNixpkgsRev = nixpkgs.rev or "";
          ryokuIsoRyokuRev = self.rev or "";
        };
        modules = [ ./nix/iso ];
      };

      mkIsoConfigSystem = {
        gpuVendors ? [ ],
        firmware ? "uefi",
        nvidiaBranch ? "stable",
        nvidiaOpen ? true,
        kernel ? "default",
      }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inputs = { };
            install = {
              hostname = "ryoku-ci";
              username = "ryoku";
              passwordHash = "*";
              inherit firmware gpuVendors nvidiaBranch nvidiaOpen;
              installDisk = "/dev/vda";
              timeZone = "UTC";
              locale = "en_US.UTF-8";
              keyboardLayout = "us";
              inherit kernel;
              compositor = "hyprland";
              browser = "chromium";
              shell = "fish";
              optionalApps = [ "prompt" ];
              binaryCache = true;
              ryokuSource = "${ryokuRepo}/unstable-dev";
              nixpkgsSource = "github:NixOS/nixpkgs/nixos-unstable";
            };
          };
          modules = [
            ryokuNixosModule
            ./nix/iso-configs/ryoku.nix
            ./nix/iso-configs/configuration.nix
          ];
        };
    in
    {
      lib.version = version;

      nixosModules.default = ryokuNixosModule;

      # Installs follow unstable-dev; ryoku-iso-stable is for images built from main.
      nixosConfigurations.ryoku-iso = mkRyokuIso "unstable-dev";
      nixosConfigurations.ryoku-iso-stable = mkRyokuIso "main";

      # Evaluation-only configuration: never activated by the installer.
      nixosConfigurations.ryoku-iso-upstream-validation =
        (mkIsoConfigSystem { }).extendModules {
          modules = [
            { programs.ryoku.upstreamPackages.enable = true; }
          ];
        };

      packages.${system} = {
        ryoku-upstream-desktop = ryokuUpstream.packages.${system}.ryoku-desktop;
        ryoku-upstream-nixos-bundle = ryokuUpstreamNixosBundle;
        ryoku-install = ryokuInstall;
        ryoku-install-backend = ryokuInstallBackend;
        ryoku-iso = self.nixosConfigurations.ryoku-iso.config.system.build.isoImage;
        ryoku-iso-stable = self.nixosConfigurations.ryoku-iso-stable.config.system.build.isoImage;
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
        ryoku-skwd-paper = ryoku.skwdPaper;
        ryoku-ryotunes = ryoku.ryotunes;
        ryomanager = ryoku.ryomanager;
        ryotunes-unwrapped = ryoku.ryotunesUnwrapped;
        ryoku-keysounds = ryoku.keysounds;
        ryoku-qmk-hid = ryoku.qmkHid;
        ryoku-waifu2x = ryoku.waifu2x;
        ryoku-helpers = ryoku.helpers;
        ryoku-nixos-system-bridge = ryoku.nixosSystemBridge;
        ryoku-desktop-data = ryoku.desktopData;
        ryoku-wm-hyprland = ryoku.wmHyprland;
        ryoku-wm-niri = ryoku.wmNiri;
        ryoku-wm-mango = ryoku.wmMango;
        ryoku-niri = ryoku.niri;
        ryoku-mango = ryoku.mango;
        ryoku-xwayland-satellite = ryoku.xwaylandSatellite;

        # Ryoku owns its compositor ABI. These come from Ryoku's
        # locked nixpkgs rather than the host's package set.
        ryoku-hyprland = pkgs.hyprland.override {
          makeWrapper = pkgs.makeBinaryWrapper;
        };
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

        ryoku-installer-disk-identity = pkgs.runCommand "ryoku-installer-disk-identity-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              gnugrep
              gnused
              python3
            ];
          }
          ''
            RYOKU_INSTALL_BACKEND_SOURCE=${./nix/apps/ryoku-install-backend.sh} \
              bash ${./nix/tests/test-installer-disk-identity.sh}
            touch "$out"
          '';

        ryoku-installer-iso = pkgs.runCommand "ryoku-installer-iso-check"
          { nativeBuildInputs = [ pkgs.python3 pkgs.gnugrep ]; }
          ''
            RYOKU_INSTALL_TEST_BACKEND=${ryokuInstallBackend}/bin/ryoku-install-backend \
            RYOKU_INSTALL_BACKEND_SOURCE=${./nix/apps/ryoku-install-backend.sh} \
              python3 ${./nix/tests/test-installer-iso.py}

            backend=${./nix/apps/ryoku-install-backend.sh}
            grep -Fq -- '--confirm-disk' "$backend"
            grep -Fq 'nixos-install' "$backend"
            grep -Fq 'Type the exact disk path' "$backend"
            grep -Fq 'refusing to erase the disk backing the live installer' "$backend"
            grep -Fq 'iso_work/ryoku-source' "$backend"
            grep -Fq 'path:./ryoku-source' "$backend"
            grep -Fq 'detect_gpu_vendors' "$backend"
            grep -Fq 'nixos-generate-config --root "$target_root" --show-hardware-config' "$backend"
            grep -Fq 'chown -R root:root "$target_root/etc/nixos"' "$backend"
            grep -Fq 'cp -a "$iso_config_templates/."' "$backend"
            grep -Fq 'user-password.hash' "$backend"
            grep -Fq 'install -m 0600 -o root -g root' "$backend"
            grep -Fq 'local install_host="ryoku"' "$backend"
            grep -Fq -- '--flake "path:$target_root/etc/nixos#$install_host"' "$backend"
            grep -Fq -- '--override-input nixpkgs "$target_nixpkgs_ref"' "$backend"
            grep -Fq -- '--override-input ryoku "$target_source_ref"' "$backend"
            grep -Fq 'choose_install_parallelism' "$backend"
            grep -Fq -- '--max-jobs "$install_jobs"' "$backend"
            grep -Fq -- '--cores "$install_cores"' "$backend"
            grep -Fq -- '--no-cache' "$backend"
            grep -Fq 'binaryCache = ''${binary_cache_nix};' "$backend"
            touch "$out"
          '';

        ryoku-iso-configs =
          let
            generic = mkIsoConfigSystem { };
            nvidia = mkIsoConfigSystem { gpuVendors = [ "nvidia" ]; };
            nvidiaLegacy580 = mkIsoConfigSystem {
              gpuVendors = [ "nvidia" ];
              nvidiaBranch = "legacy_580";
              nvidiaOpen = false;
            };
            nvidiaLegacy470 = mkIsoConfigSystem {
              gpuVendors = [ "nvidia" ];
              nvidiaBranch = "legacy_470";
              nvidiaOpen = false;
            };
            amd = mkIsoConfigSystem { gpuVendors = [ "amd" ]; };
            intel = mkIsoConfigSystem { gpuVendors = [ "intel" ]; };
            hybrid = mkIsoConfigSystem { gpuVendors = [ "nvidia" "intel" ]; };
            bios = mkIsoConfigSystem { firmware = "bios"; };
            latestKernel = mkIsoConfigSystem { kernel = "latest"; };
            zenKernel = mkIsoConfigSystem { kernel = "zen"; };
          in
          assert generic.config.networking.hostName == "ryoku-ci";
          assert generic.config.programs.ryoku.enable;
          assert generic.config.programs.ryoku.binaryCache.enable;
          assert generic.config.nix.package == nixpkgs.legacyPackages.${system}.nixVersions.latest;
          assert nvidia.config.services.xserver.videoDrivers == [ "nvidia" ];
          assert nvidia.config.hardware.nvidia.modesetting.enable;
          assert nvidia.config.hardware.nvidia.branch == "stable";
          assert nvidia.config.hardware.nvidia.open;
          assert nvidiaLegacy580.config.hardware.nvidia.branch == "legacy_580";
          assert !nvidiaLegacy580.config.hardware.nvidia.open;
          assert nvidiaLegacy470.config.hardware.nvidia.branch == "legacy_470";
          assert !nvidiaLegacy470.config.hardware.nvidia.open;
          assert builtins.elem "amdgpu" amd.config.boot.initrd.kernelModules;
          assert builtins.elem "i915" intel.config.boot.initrd.kernelModules;
          assert builtins.length intel.config.hardware.graphics.extraPackages >= 2;
          assert hybrid.config.services.xserver.videoDrivers == [ "nvidia" ];
          assert builtins.elem "i915" hybrid.config.boot.initrd.kernelModules;
          assert bios.config.boot.loader.grub.enable;
          assert bios.config.boot.loader.grub.devices == [ "/dev/vda" ];
          assert !bios.config.boot.loader.systemd-boot.enable;
          assert latestKernel.config.boot.kernelPackages.kernel.version == nixpkgs.legacyPackages.${system}.linuxPackages_latest.kernel.version;
          assert zenKernel.config.boot.kernelPackages.kernel.version == nixpkgs.legacyPackages.${system}.linuxPackages_zen.kernel.version;
          pkgs.runCommand "ryoku-iso-configs-check" { } ''
            touch "$out"
          '';

        ryoku-installer-wrapper = import ./nix/tests/installer-wrapper.nix {
          inherit pkgs;
          installer = ryokuInstall;
        };

        ryoku-phone = import ./nix/tests/phone.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };

        ryoku-display-manager = import ./nix/tests/display-manager.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };

        # Core runtime
        ryoku-shell = ryoku.shell;

        # Python is a bar style, not a second eagerly preloaded shell. Keep its
        # panel stack demand-loaded and consume Ryoku's live settings stream
        # instead of spawning a parallel inotify loop at idle.
        ryoku-python-idle-contract = pkgs.runCommand
          "ryoku-python-idle-contract-check"
          { nativeBuildInputs = [ pkgs.gnugrep ]; }
          ''
            main=${./ryoku/shell/quickshell/shell/modules/bar/barstyles/python/Main.qml}

            grep -Fq 'let cachedItem = ensureWidgetItem(newWidget, t);' "$main"
            grep -Fq 'function syncLiveSettings()' "$main"
            grep -Fq 'onSettingsLoaded() { masterWindow.syncLiveSettings(); }' "$main"

            ! grep -Fq 'preloadStaggerTimer' "$main"
            ! grep -Fq 'settingsWatcher' "$main"
            ! grep -Fq 'inotifywait' "$main"

            touch "$out"
          '';
        ryoku-cli = ryoku.cli;
        ryoku-hub = ryoku.hub;
        ryoku-palette-bridge = ryoku.paletteBridge;
        ryoku-rashin = ryoku.rashin;
        ryoku-ryostore = ryoku.ryostore;
        ryoku-ryomotion = ryoku.ryomotion;
        ryoku-ryovm-helpers = ryoku.ryovmHelpers;
        ryoku-livewall = ryoku.livewall;
        ryoku-ryogami = ryoku.ryogami;
        ryoku-skwd-paper = ryoku.skwdPaper;
        ryoku-ryotunes = ryoku.ryotunes;
        ryomanager = ryoku.ryomanager;
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
        ryoku-wm-mango = ryoku.wmMango;
        ryoku-niri = ryoku.niri;
        ryoku-mango = ryoku.mango;
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
            work="$TMPDIR/ryoku-gpu-mux"

            mkdir -p "$work/tests" "$work/system/hardware"

            cp ${self}/tests/gpu-mux.sh "$work/tests/"
            cp -R ${self}/system/hardware/gpu "$work/system/hardware/"

            mkdir -p "$work/system/hardware/power"
            cp ${self}/system/hardware/power/ryoku-hw-laptop               "$work/system/hardware/power/"

            chmod -R u+w "$work"
            patchShebangs "$work"

            bash "$work/tests/gpu-mux.sh"
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
            work="$TMPDIR/ryoku-gpu-pin"

            mkdir -p "$work/tests" "$work/system/hardware"

            cp ${self}/tests/gpu-pin-policy.sh "$work/tests/"
            cp -R ${self}/system/hardware/gpu "$work/system/hardware/"

            mkdir -p "$work/system/hardware/power"
            cp ${self}/system/hardware/power/ryoku-hw-laptop               "$work/system/hardware/power/"

            chmod -R u+w "$work"
            patchShebangs "$work"

            bash "$work/tests/gpu-pin-policy.sh"
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

        ryoku-barstyle-source-integrity = pkgs.runCommand
          "ryoku-barstyle-source-integrity-check"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            RYOKU_QSBAR_VARIANT=${./ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/VariantRoot.qml} \
            RYOKU_BAR_PRODUCTS=${./ryoku/shell/quickshell/shell/services/BarProducts.qml} \
            RYOKU_PYTHON_BARSTYLE=${./ryoku/shell/quickshell/shell/modules/bar/barstyles/python} \
              python3 ${./nix/tests/test-barstyle-source-integrity.py}

            touch "$out"
          '';

        ryoku-session-bootstrap = pkgs.runCommand
          "ryoku-session-bootstrap-check"
          {
            nativeBuildInputs = [ pkgs.gnugrep ];
          }
          ''
            for autostart in ${ryoku.desktopData}/share/ryoku/config/hypr/modules/autostart.lua \
                             ${ryoku.desktopData}/share/ryoku/config/niri/autostart.kdl \
                             ${ryoku.desktopData}/share/ryoku/config/mango/autostart.conf
            do
              grep -Fq 'ryoku-nix-session-start' "$autostart"
            done

            session_module=${./nix/modules/ryoku.nix}
            grep -Fq 'dbus-update-activation-environment --systemd --all' "$session_module"
            grep -Fq "''${materializer}/bin/ryoku-materialize || true" "$session_module"
            grep -Fq 'systemctl --user restart ryoku-session.target' "$session_module"

            niri_module=${./nix/modules/ryoku.nix}
            niri_wrapper="$TMPDIR/niri-session-wrapper-source"
            sed -n '/cat > "$out\/bin\/ryoku-niri-session"/,/chmod 0755/p' "$niri_module" > "$niri_wrapper"
            grep -Fq "''${materializer}/bin/ryoku-materialize" "$niri_wrapper"
            grep -Fq 'exec ''${ryokuNiri}/bin/niri-session' "$niri_wrapper"
            if grep -Fq '[ ! -f "$config_home/niri/config.kdl" ]' "$niri_wrapper"; then
              echo 'Niri session wrapper still conditionally skips generation materialization' >&2
              exit 1
            fi

            touch "$out"
          '';

        ryoku-notification-ownership = pkgs.runCommand
          "ryoku-notification-ownership-check"
          {
            nativeBuildInputs = [ pkgs.python3 ];
          }
          ''
            RYOKU_NIX_MODULE=${./nix/modules/ryoku.nix} \
            RYOKU_SHELL_QML=${./ryoku/shell/quickshell/shell/shell.qml} \
            RYOKU_NOTIFS_QML=${./ryoku/shell/quickshell/shell/services/Notifs.qml} \
            RYOKU_SCHEME_QML=${./ryoku/shell/quickshell/shell/services/Scheme.qml} \
            RYOKU_NOTIFICATION_CARD_QML=${./ryoku/shell/quickshell/shell/modules/notifications/NotificationCard.qml} \
            RYOKU_IRIS_THEME_QML=${./ryoku/shell/quickshell/inir/services/MaterialThemeLoader.qml} \
              python3 ${./nix/tests/test-notification-ownership.py}

            touch "$out"
          '';

        ryoku-bt-audio-watch-singleton = pkgs.runCommand
          "ryoku-bt-audio-watch-singleton-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              python3
              util-linux
            ];
          }
          ''
            RYOKU_BT_AUDIO_TEST_HELPER=${./system/hardware/audio/ryoku-bt-audio} \
              python3 ${./nix/tests/test-bt-audio-watch-singleton.py}

            touch "$out"
          '';

        ryoku-qylock-staging-cleanup = pkgs.runCommand
          "ryoku-qylock-staging-cleanup-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              findutils
              gnugrep
              procps
              python3
              util-linux
            ];
          }
          ''
            RYOKU_QYLOCK_TEST_INSTALLER=${./ryoku/lockscreen/install-qylock} \
              python3 ${./nix/tests/test-qylock-staging-cleanup.py}

            touch "$out"
          '';

        ryoku-qylock-pam-materialization = pkgs.runCommand
          "ryoku-qylock-pam-materialization-check"
          { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            RYOKU_QYLOCK_NIX_MODULE=${./nix/modules/ryoku.nix} \
              python3 ${./nix/tests/test-qylock-pam-materialization.py}

            touch "$out"
          '';

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
