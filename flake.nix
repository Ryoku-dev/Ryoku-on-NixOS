{
  description = "Nix packaging for the Ryoku desktop";

  inputs = {
    ryokuUpstream.url = "github:Ryoku-dev/ryoku/unstable-dev";
    ryokuHyperion.url = "github:Ryoku-dev/ryoku/hyperion";
    ryomarket.url = "github:Ryoku-dev/ryomarket/feature/hyperion-v2";

    # Ryotunes 2.0, the Lithic rewrite Hyperion is built around (its window
    # rules and docs/lithic target it). Hyperion's own flake still pins the
    # retired 1.2.0 Rust/Quickshell app.
    hyperionRyotunesSrc = {
      url = "github:Ryoku-dev/ryotunes/hyperion";
      flake = false;
    };

    # Ryoport's hyperion branch: the v1.0.0 fixes for the Ryoku v2 line.
    # Built in Hyperion's package set, as upstream builds the v1.0.0 pin.
    hyperionRyoport = {
      url = "github:Ryoku-dev/ryoport/hyperion";
      inputs.nixpkgs.follows = "ryokuHyperion/nixpkgs";
    };

    # Compatibility input for existing consumers which follow their host
    # nixpkgs. Ryoku-owned packages deliberately do not build from this input.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Fixed package universe for Ryoku itself. Keeping this independent of the
    # host prevents fetchPnpmDeps and other fixed-output builders from changing
    # underneath a Ryoku release when the host updates nixos-unstable.
    ryokuPackagesNixpkgs.url =
      "github:NixOS/nixpkgs/1c89083e451e891152365b799595cf7790a43325";

    inirSrc = {
      url = "github:snowarch/iNiR/48cdcecb0f6089cfbb7019054602eab28e154b3b";
      flake = false;
    };

    skwdWall = {
      url = "github:liixini/skwd-wall/nix";
    };

    hyprglassSrc = {
      url = "github:hyprnux/hyprglass/v1.1.1";
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
  };

  outputs = { self, ryokuUpstream, ryokuHyperion, ryomarket, hyperionRyotunesSrc, hyperionRyoport, nixpkgs, ryokuPackagesNixpkgs, skwdWall, hyprglassSrc, bibataMaterialSrc, imgbordersSrc, inirSrc, ... }:
    let
      version =
        builtins.replaceStrings
          [ "\n" "\r" ]
          [ "" "" ]
          (builtins.readFile ./VERSION);

      system = "x86_64-linux";

      quickshellScreencopyFixOverlay = import ./nix/packages/quickshell-screencopy-overlay.nix;

      hyprDynamicCursorsOverlay = final: prev: {
        hyprlandPlugins = prev.hyprlandPlugins // {
          hypr-dynamic-cursors =
            prev.hyprlandPlugins.hypr-dynamic-cursors.overrideAttrs (_old: {
              version = "0-unstable-2026-10-05";

              src = final.fetchFromGitHub {
                owner = "VirtCode";
                repo = "hypr-dynamic-cursors";
                rev = "2a8d0b735328d874a78ca93b2f201649f712a74a";
                hash = "sha256-PSt/SRtemvsoGYNFJ7YLiXGxT8EJe3AhmGwt5Vt79aA=";
              };
            });
        };
      };

      pkgs = import ryokuPackagesNixpkgs {
        inherit system;
        overlays = [
          quickshellScreencopyFixOverlay
          hyprDynamicCursorsOverlay
        ];
      };

      skwdPaper = skwdWall.packages.${system}.skwd-paper;

      ryoku = import ./nix/packages {
        inherit
          pkgs
          hyprglassSrc
          bibataMaterialSrc
          imgbordersSrc
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

      # Hyperion onboarding. Also published as its own flake under
      # nix/bootstrap; both evaluate to this derivation.
      ryokuV2 = import ./nix/bootstrap/package.nix { inherit pkgs; };

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

      # Hyperion's own package universe: its nixpkgs pin plus the quickshell
      # overlay its flake applies (identical to ours), so the derivations
      # imported below are the same ones the Hyperion flake exports.
      hyperionPkgs = import ryokuHyperion.inputs.nixpkgs {
        inherit system;
        overlays = [ quickshellScreencopyFixOverlay ];
      };

      hyperionRyoku = import ./nix/packages/hyperion-upstream.nix {
        inherit ryokuHyperion system;
        pkgs = hyperionPkgs;
      };

      # Apps Arch Hyperion treats as optional (ryoku-desktop optdepends and
      # the independently released Ryotunes and Ryoport). They are not part
      # of the system: RyoMarket's Hyperion edition installs them into the
      # user's Nix profile from the packages below, and
      # ryoku-hyperion-shipped-apps delivers the shipped ones once.
      hyperionOptionalApps = with hyperionRyoku; [ ryotunes ryoport ryomanager waifu2x qmkHid ];
      # Retired from Arch Hyperion; upstream's Nix bundle still lists it.
      hyperionRetired = [ hyperionRyoku.ryomotion ];
      hyperionRyoportPackage = hyperionRyoport.packages.${system}.default;

      # Upstream's bundle (Hyperion nix/packages/default.nix) without those.
      # The Niri-only bundle also drops wmHyprland.
      # ryoku-hyperion-bundle-provenance checks both against upstream.
      # Upstream's bundle lists store path strings, so compare by path.
      withoutPaths = drop: builtins.filter
        (p: !(builtins.elem (toString p) (map toString drop)));
      hyperionComponents =
        withoutPaths (hyperionOptionalApps ++ hyperionRetired) hyperionRyoku.bundle.paths;
      hyperionNiriOnlyComponents =
        withoutPaths [ hyperionRyoku.wmHyprland ] hyperionComponents;

      # The NixOS bridge must take precedence over upstream helpers with the
      # same executable names.
      hyperionNixosBridges = [
        ryoku.nixosSystemBridge
        ryoku.nixUpdate
      ];

      hyperionQmlRuntime = import ./nix/packages/hyperion-qml-runtime.nix {
        pkgs = hyperionPkgs;
        src = ryokuHyperion;
        upstreamQml = ryokuHyperion.packages.${system}.ryoku-qml;
      };

      hyperionRyotunes = import ./nix/packages/hyperion-ryotunes.nix {
        inherit pkgs;
        src = hyperionRyotunesSrc;
        version = builtins.replaceStrings [ "\n" ] [ "" ]
          (builtins.readFile (hyperionRyotunesSrc + "/VERSION"));
      };

      # The QML tree compositor-spawned surfaces see (upstream's binds set
      # QML_IMPORT_PATH to ~/.local/lib/qt6/qml, where Arch also has
      # /usr/lib/qt6/qml as fallback): Hyperion's Ryoku modules, Ryogami's
      # and the Qt add-on modules of Hyperion's own Qt. qtdeclarative and
      # Quickshell's modules are built into qs.
      hyperionUserQml = hyperionPkgs.buildEnv {
        name = "ryoku-hyperion-user-qml";
        paths = [
          hyperionQmlRuntime
          hyperionRyoku.ryogami
          hyperionPkgs.qt6.qtmultimedia
          hyperionPkgs.qt6.qtquick3d
          hyperionPkgs.qt6.qtwayland
          hyperionPkgs.qt6.qt5compat
          hyperionPkgs.kdePackages.kirigami.unwrapped
          hyperionPkgs.kdePackages.syntax-highlighting
        ];
        pathsToLink = [ "/lib/qt-6/qml" ];
      };

      mkHyperionMaterializer = niriOnly:
        import ./nix/apps/ryoku-materialize.nix {
          inherit pkgs niriOnly;
          hyperion = true;
          userQml = hyperionUserQml;
          ryoku = ryoku // {
            cli = hyperionRyoku.cli;
            desktopData = hyperionRyoku.desktopData;
            qml = hyperionQmlRuntime;
            wmNiri = hyperionRyoku.wmNiri;
            wmHyprland = hyperionRyoku.wmHyprland;
          };
        };

      hyperionMaterializer = mkHyperionMaterializer false;
      hyperionNiriMaterializer = mkHyperionMaterializer true;

      # Isolated v2 composition. It is not part of the active desktop or ISO.
      ryokuHyperionNixosBundle = pkgs.symlinkJoin {
        name = "ryoku-hyperion-nixos-bundle";
        paths = hyperionNixosBridges ++ hyperionComponents;
      };

      # Isolated Niri-only v2 composition for programs.ryoku.hyperionNiriOnly.
      ryokuHyperionNiriNixosBundle = pkgs.symlinkJoin {
        name = "ryoku-hyperion-niri-nixos-bundle";
        paths = hyperionNixosBridges ++ hyperionNiriOnlyComponents;
      };

      ryokuShima = import ./nix/packages/ryoku-shima.nix { inherit pkgs; src = inirSrc; };

      ryokuNixosModule =
        import ./nix/modules/ryoku.nix {
          inherit self ryokuUpstream ryokuHyperion ryomarket;
          ryokuNixpkgs = pkgs;
          ryokuHyperionNixpkgs = hyperionPkgs;
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

      # Evaluation-only preview. No ISO or installed system follows this.
      nixosConfigurations.ryoku-iso-hyperion-validation =
        (mkIsoConfigSystem { }).extendModules {
          modules = [
            { programs.ryoku.hyperionPackages.enable = true; }
          ];
        };

      packages.${system} = {
        ryoku-shima = ryokuShima;
        ryoku-v2 = ryokuV2;
        ryoku-hyperion-qml-runtime = hyperionQmlRuntime;
        ryoku-hyperion-user-qml = hyperionUserQml;
        ryoku-hyperion-materialize = hyperionMaterializer;
        ryoku-hyperion-niri-materialize = hyperionNiriMaterializer;
        ryomarket-hyperion = ryomarket.packages.${system}.ryomarket;
        ryotunes = hyperionRyotunes;
        ryostore = hyperionRyoku.ryostore;
        ryoport = hyperionRyoportPackage;
        ryomanager = hyperionRyoku.ryomanager;
        waifu2x-ncnn-vulkan = hyperionRyoku.waifu2x;
        qmk-hid = hyperionRyoku.qmkHid;
        rashin = hyperionRyoku.rashin;
        ryoku-hyperion-desktop = ryokuHyperion.packages.${system}.ryoku-desktop;
        ryoku-hyperion-nixos-bundle = ryokuHyperionNixosBundle;
        ryoku-hyperion-niri-nixos-bundle = ryokuHyperionNiriNixosBundle;
        ryoku-upstream-desktop = ryokuUpstream.packages.${system}.ryoku-desktop;
        ryoku-upstream-nixos-bundle = ryokuUpstreamNixosBundle;
        ryoku-install = ryokuInstall;
        ryoku-install-backend = ryokuInstallBackend;
        ryoku-iso = self.nixosConfigurations.ryoku-iso.config.system.build.isoImage;
        ryoku-iso-stable = self.nixosConfigurations.ryoku-iso-stable.config.system.build.isoImage;
        # The system a default install builds; nix-cache.yml pushes it to the
        # binary cache so installs and updates download Ryoku instead of
        # compiling it.
        ryoku-default-system = (mkIsoConfigSystem { }).config.system.build.toplevel;
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
        ryoku-ryostore = ryoku.ryostore;
        ryoku-livewall = ryoku.livewall;
        ryoku-ryogami = ryoku.ryogami;
        ryoku-skwd-paper = ryoku.skwdPaper;
        ryoku-keysounds = ryoku.keysounds;
        ryoku-qmk-hid = ryoku.qmkHid;
        ryoku-waifu2x = ryoku.waifu2x;
        ryoku-helpers = ryoku.helpers;
        ryoku-nixos-system-bridge = ryoku.nixosSystemBridge;
        ryoku-desktop-data = ryoku.desktopData;
        ryoku-wm-hyprland = ryoku.wmHyprland;
        ryoku-wm-niri = ryoku.wmNiri;
        ryoku-niri = ryoku.niri;
        ryoku-xwayland-satellite = ryoku.xwaylandSatellite;

        # Ryoku owns its compositor ABI. These come from Ryoku's
        # locked nixpkgs rather than the host's package set.
        ryoku-hyprland = pkgs.hyprland.override {
          makeBinaryWrapper = pkgs.makeBinaryWrapper;
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

        default = ryoku.bundle;
      };

      apps.${system} = {
        ryoku-v2 = {
          type = "app";
          program = "${ryokuV2}/bin/ryoku-v2";
        };

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
        ryoku-shima-store-universe = pkgs.runCommand "ryoku-shima-store-universe-check"
          { nativeBuildInputs = [ pkgs.python3 ]; } ''
            python3 ${./nix/tests/test-shima-install-source.py} \
              --project-lock ${./flake.lock} \
              --install-source ${import ./nix/packages/shima-install-source.nix { inherit pkgs; src = self; }} \
              --overlay ${./nix/packages/quickshell-screencopy-overlay.nix} \
              --tokens ${./ryoku/ui/Singletons/Tokens.qml}
            touch "$out"
          '';

        ryoku-shima-appearance = pkgs.runCommand "ryoku-shima-appearance-check"
          { nativeBuildInputs = [ pkgs.python3 pkgs.bash ]; } ''
            python3 ${./nix/tests/test-shima-appearance.py} --runtime ${ryokuShima}
            touch "$out"
          '';

        ryoku-shima-layout = pkgs.runCommand "ryoku-shima-layout" {} ''
          test -x ${ryokuShima}/bin/ryoku-shima
          test ! -e ${ryokuShima}/bin/inir
          test -f ${ryokuShima}/share/quickshell/inir/LICENSE
          for family in Iris Ii Waffle; do
            test -f ${ryokuShima}/share/quickshell/inir/Shell''${family}Panels.qml
          done
          ${ryokuShima}/bin/ryoku-shima --version | grep -F '2.33.0'
          touch "$out"
        '';

        # RyoStore builds Shima from the generated install source with a pure
        # flake evaluation. It must evaluate on its own, to the same derivation
        # the flake ships.
        ryoku-subshell-store-source = pkgs.runCommand "ryoku-subshell-store-source-check"
          { nativeBuildInputs = [ pkgs.python3 pkgs.nix ]; } ''
            python3 ${./nix/tests/test-subshell-store-source.py} \
              --install-source ${import ./nix/packages/shima-install-source.nix { inherit pkgs; src = self; }} \
              --nixpkgs ${ryokuPackagesNixpkgs} \
              --inir ${inirSrc} \
              --expected-drv ${builtins.unsafeDiscardStringContext ryokuShima.drvPath}
            touch "$out"
          '';

        # The packaged runtime is the only Shima on a NixOS PATH. The models
        # mirror system-path (package order, first command wins), restricted
        # to Ryoku's own packages like ryoku-bridge-command-ownership.
        ryoku-subshell-nix-ownership =
          let
            systemPathModel = name: host: pkgs.buildEnv {
              inherit name;
              paths = builtins.filter
                (pkg: pkgs.lib.hasPrefix "ryoku" (pkgs.lib.getName pkg))
                host.config.environment.systemPackages;
              pathsToLink = [ "/bin" ];
              ignoreCollisions = true;
            };
            host = mkIsoConfigSystem { };
            shimaHost = host.extendModules {
              modules = [ { programs.ryoku.shima.enable = true; } ];
            };
          in
          pkgs.runCommand "ryoku-subshell-nix-ownership-check"
            { nativeBuildInputs = [ pkgs.python3 ]; } ''
              python3 ${./nix/tests/test-subshell-nix-ownership.py} \
                --shima ${ryokuShima} \
                --system-path ${systemPathModel "ryoku-shima-system-path-model" shimaHost} \
                --system-path-without-shima ${systemPathModel "ryoku-system-path-model" host} \
                --desktop-data ${ryoku.desktopData}
              touch "$out"
            '';

        # Every host patch reaches the built runtime, and the injected bridge
        # routes surfaces to Ryoku's tools the same way as the Arch runtime.
        ryoku-subshell-runtime = pkgs.runCommand "ryoku-subshell-runtime-check"
          { nativeBuildInputs = [ pkgs.python3 pkgs.git pkgs.nodejs ]; } ''
            python3 ${./nix/tests/test-subshell-runtime.py} \
              --runtime ${ryokuShima} \
              --patch-dir ${./nix/packages/shima} \
              --patch-dir ${./ryoku/shell/quickshell/inir/patches} \
              --arch-overlay-patch ${./ryoku/shell/quickshell/shima-overlay/runtime.patch}
            touch "$out"
          '';

        # The Python subshell's weather refresh does not start a refresh chain
        # while the shell daemon cannot persist the location.
        ryoku-subshell-python-weather = pkgs.runCommand "ryoku-subshell-python-weather-check"
          {
            nativeBuildInputs = with pkgs; [ bash coreutils gnugrep gnused jq procps util-linux ];
          } ''
            # The scripts call each other through /usr/bin/env, which the
            # build sandbox lacks.
            cp -r ${./ryoku/shell/quickshell/shell/modules/bar/barstyles/python/scripts} scripts
            chmod -R u+w scripts
            patchShebangs scripts
            RYOKU_PYTHON_SCRIPTS="$PWD/scripts" \
              bash ${./tests/subshell-python-weather-recursion.sh}
            touch "$out"
          '';

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

        # Verify the packaged installer and backend through a PTY dry run.
        ryoku-installer-tui = pkgs.runCommand "ryoku-installer-tui-check"
          { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            RYOKU_INSTALL_TEST_BINARY=${ryokuInstall}/bin/ryoku-install \
              python3 ${./nix/tests/test-installer-tui.py}
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

        ryoku-bridge-command-ownership =
          let
            host = (mkIsoConfigSystem { }).config;
          in
          import ./nix/tests/bridge-command-ownership.nix {
            inherit pkgs;
            bridge = ryoku.nixosSystemBridge;
            helpers = ryoku.helpers;
            bundle = ryoku.bundle;
            shell = ryoku.shell;
            cli = ryoku.cli;
            systemPackages = host.environment.systemPackages;
            polkitRules = host.security.polkit.extraConfig;
          };

        ryoku-installer-wrapper = import ./nix/tests/installer-wrapper.nix {
          inherit pkgs;
          installer = ryokuInstall;
        };

        ryoku-phone = import ./nix/tests/phone.nix {
          inherit pkgs;
          module = self.nixosModules.default;
        };

        # Hosts evaluate the module with their nixpkgs input, whose NixOS
        # display-manager modules are what Ryoku's defaults interact with.
        ryoku-display-manager = import ./nix/tests/display-manager.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          module = self.nixosModules.default;
        };

        ryoku-hyperion-niri-only = import ./nix/tests/hyperion-niri-only.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          module = self.nixosModules.default;
          hyperionPackages = ryokuHyperion.packages.${system};
          ryokuPackages = self.packages.${system};
        };

        ryoku-hyperion-bundle-provenance = import ./nix/tests/hyperion-bundle-provenance.nix {
          inherit pkgs hyperionRyoku hyperionOptionalApps hyperionRetired;
          hyperionPackages = ryokuHyperion.packages.${system};
          bridges = hyperionNixosBridges;
          fullBundle = ryokuHyperionNixosBundle;
          niriBundle = ryokuHyperionNiriNixosBundle;
        };

        # The default install's login sessions, read from its evaluated config.
        ryoku-firstboot-session = import ./nix/tests/firstboot-session.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          config = (mkIsoConfigSystem { }).config;
        };

        # Runs the default install's greeter guard unit as systemd starts it.
        ryoku-firstboot-greeter-guard =
          let
            unit = (mkIsoConfigSystem { }).config.systemd.services.ryoku-greeter-guard;
          in
          pkgs.runCommand "ryoku-firstboot-greeter-guard-check" { } ''
            GUARD=${unit.serviceConfig.ExecStart} \
            SERVICE_PATH=${unit.environment.PATH} \
              ${pkgs.bash}/bin/bash ${./nix/tests/test-firstboot-greeter-guard.sh}
            touch "$out"
          '';

        # Third-party QML imports of the shell against the default install's
        # ryoku-shell.service import path. Ryoku's own QML entries are dropped
        # from the build inputs so the check needs only the Qt packages.
        ryoku-firstboot-qml-imports =
          let
            qmlPath = (mkIsoConfigSystem { }).config.systemd.user.services.ryoku-shell.environment.QML2_IMPORT_PATH;
            thirdParty = builtins.appendContext
              (builtins.unsafeDiscardStringContext qmlPath)
              (nixpkgs.lib.filterAttrs (drv: _: !(nixpkgs.lib.hasInfix "-ryoku-" drv))
                (builtins.getContext qmlPath));
          in
          pkgs.runCommand "ryoku-firstboot-qml-imports-check"
            { nativeBuildInputs = [ pkgs.python3 ]; }
            ''
              python3 ${./nix/tests/test-firstboot-qml-imports.py} "${thirdParty}" \
                ${./ryoku/shell/quickshell} ${./ryoku/ui}
              touch "$out"
            '';

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
        ryoku-ryostore = ryoku.ryostore;
        ryoku-livewall = ryoku.livewall;
        ryoku-ryogami = ryoku.ryogami;
        ryoku-skwd-paper = ryoku.skwdPaper;
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
        ryoku-niri = ryoku.niri;
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
        ryoku-nix-track-edit = pkgs.runCommand "ryoku-nix-track-edit-check"
          { nativeBuildInputs = [ pkgs.python3 ]; } ''
            cp -r ${./nix/scripts} scripts
            cp -r ${./nix/tests} tests
            mkdir iso-configs && cp ${./nix/iso-configs/ryoku.nix} iso-configs/ryoku.nix
            python3 tests/test-ryoku-nix-track-edit.py
            touch "$out"
          '';

        # Onboarding must not drag in gh (gnupg, pcsclite), a second Nix,
        # or anything of the desktop, and the bootstrap flake must produce
        # the same command as this flake.
        ryoku-v2-bootstrap = pkgs.runCommand "ryoku-v2-bootstrap-check"
          {
            closure = pkgs.closureInfo { rootPaths = [ ryokuV2 ]; };
            bootstrapLock = ./nix/bootstrap/flake.lock;
            projectLock = ./flake.lock;
            nativeBuildInputs = [ pkgs.jq ];
          } ''
            for forbidden in '-gh-[0-9]' '-gnupg-' '-pcsclite-' '-nix-[0-9]' '-nixos-rebuild' \
                '-systemd-[0-9]' '-quickshell-' '-ryoku-shell' '-ryoku-qml' '-hyprland-' '-niri-'; do
              if grep -E -- "$forbidden" "$closure/store-paths"; then
                echo "ryoku-v2 closure contains $forbidden" >&2
                exit 1
              fi
            done
            test "$(jq -r .nodes.nixpkgs.locked.rev "$bootstrapLock")" = \
                 "$(jq -r .nodes.ryokuPackagesNixpkgs.locked.rev "$projectLock")"
            test "$(jq -r .nodes.nixpkgs.locked.narHash "$bootstrapLock")" = \
                 "$(jq -r .nodes.ryokuPackagesNixpkgs.locked.narHash "$projectLock")"
            touch "$out"
          '';

        ryoku-hyperion-shipped-apps = pkgs.runCommand "ryoku-hyperion-shipped-apps-check"
          { nativeBuildInputs = with pkgs; [ bash coreutils gnugrep jq ]; } ''
            RYOKU_SHIPPED_APPS=${./nix/scripts/ryoku-hyperion-shipped-apps} \
              bash ${./nix/tests/test-hyperion-shipped-apps.sh}
            touch "$out"
          '';

        # Every app RyoMarket's Hyperion edition offers is a package here.
        ryoku-hyperion-optional-apps = pkgs.runCommand "ryoku-hyperion-optional-apps-check" { } ''
          test -x ${hyperionRyotunes}/bin/ryotunes
          test -x ${hyperionRyoportPackage}/bin/ryoport
          test -x ${hyperionRyoku.ryomanager}/bin/ryomanager
          test -x ${hyperionRyoku.waifu2x}/bin/waifu2x-ncnn-vulkan
          test -x ${hyperionRyoku.qmkHid}/bin/qmk_hid
          touch "$out"
        '';

        ryoku-hyperion-retire-ryotunes = pkgs.runCommand "ryoku-hyperion-retire-ryotunes-check"
          { nativeBuildInputs = with pkgs; [ bash coreutils gnugrep procps ]; } ''
            RYOKU_RETIRE_RYOTUNES=${./nix/scripts/ryoku-hyperion-retire-ryotunes} \
              bash ${./nix/tests/test-retire-ryotunes.sh}
            touch "$out"
          '';

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

        # Interrupted update / channel switch must stop and restore state
        ryoku-nix-update-interrupt = pkgs.runCommand
          "ryoku-nix-update-interrupt-check"
          {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              git
              gnugrep
              jq
              python3
              util-linux
            ];
          }
          ''
            RYOKU_NIX_UPDATE_TEST_HELPER=${./nix/scripts/ryoku-nix-update} \
              bash ${./nix/tests/test-nix-update-interrupt.sh}
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
                             ${ryoku.desktopData}/share/ryoku/config/niri/autostart.kdl
            do
              grep -Fq 'ryoku-nix-session-start' "$autostart"
            done

            session_module=${./nix/modules/ryoku.nix}
            grep -Fq 'dbus-update-activation-environment --systemd --all' "$session_module"
            grep -Fq '    ''${materializeBestEffort}' "$session_module"
            grep -Fq 'systemctl --user restart ryoku-session.target' "$session_module"

            niri_module=${./nix/modules/ryoku.nix}
            niri_wrapper="$TMPDIR/niri-session-wrapper-source"
            sed -n '/cat > "$out\/bin\/ryoku-niri-session"/,/chmod 0755/p' "$niri_module" > "$niri_wrapper"
            grep -Fq "''${materializeBestEffort}" "$niri_wrapper"
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

        ryoku-materialize-session = import ./nix/tests/materialize-session.nix {
          inherit pkgs self;
        };
        ryoku-sddm-theme-apply = pkgs.runCommand
          "ryoku-sddm-theme-apply-check"
          { nativeBuildInputs = [ pkgs.coreutils pkgs.findutils ]; }
          ''
            RYOKU_PATH=${self} bash ${./nix/tests/test-sddm-theme-apply.sh}

            touch "$out"
          '';

        ryoku-ci-check-coverage = pkgs.runCommand
          "ryoku-ci-check-coverage"
          { nativeBuildInputs = [ pkgs.python3 ]; }
          ''
            RYOKU_CI_ROOT=${self} python3 ${./nix/tests/test-ci-check-coverage.py}
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
