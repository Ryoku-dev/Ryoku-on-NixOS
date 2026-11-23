# Assemble an ISO from a payload prepared by build.sh. Never change the online ISO.
{ self, nixpkgs, ryokuInstall, ryokuRepo }:
{ storePaths, sourcePaths, derivationsArchive, payloadFlake ? self }:
assert storePaths != [ ] && sourcePaths != [ ];
assert builtins.all (path: !(nixpkgs.lib.hasSuffix ".drv" path)) storePaths;
assert payloadFlake.lib.offlineProfile == "niri-latest-firefox-minimal-v2";
let
  system = "x86_64-linux";
  iso = nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      inherit self ryokuRepo;
      ryokuIsoChannel = "offline-minimal";
      ryokuIsoNixpkgsRev = nixpkgs.rev or "";
      ryokuIsoRyokuRev = self.rev or "";
      ryokuInstall = offlineInstaller;
    };
    modules = [
      ../default.nix
      ({ lib, ... }: {
        isoImage.storeContents = map builtins.storePath storePaths;
        # This image carries build tools/sources as well as the desktop. Avoid
        # spending the final assembly recompressing that large payload with XZ.
        isoImage.squashfsCompression = "zstd -Xcompression-level 6";
        boot.kernelPackages = pkgs.linuxPackages_latest;
        boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" "btrfs" "iso9660" "squashfs" ];
        environment.sessionVariables = {
          RYOKU_INSTALL_OFFLINE = "${sources}";
          RYOKU_INSTALL_TARGET_SOURCE = lib.mkForce "path:${payloadFlake}";
          RYOKU_INSTALL_TARGET_TRACK = lib.mkForce "path:${payloadFlake}";
          RYOKU_INSTALL_NIXPKGS_SOURCE = lib.mkForce "path:${payloadFlake.inputs.nixpkgs}";
        };
        environment.etc."ryoku/offline-README.md".text = ''
          This standalone ISO opens the guided installer automatically on TTY1.
          Run ryoku-install --iso to reopen it. Network access is disabled for
          the installer; its sources, recipes and packages come from the media.
        '';
      })
    ];
  };
  pkgs = iso.pkgs;
  recipes = builtins.storePath derivationsArchive;
  startInstaller = pkgs.writeShellApplication {
    name = "ryoku-start-offline-installer";
    runtimeInputs = [ pkgs.gzip pkgs.nixVersions.latest pkgs.coreutils ];
    text = ''
      stamp=/run/${baseNameOf recipes}.imported
      if [ ! -e "$stamp" ]; then
        echo 'Loading offline build recipes from the installation medium...'
        gzip -dc ${recipes} | nix-store --import >/dev/null
        touch "$stamp"
      fi
      exec ${ryokuInstall}/bin/ryoku-install "$@"
    '';
  };
  sources = pkgs.linkFarm "ryoku-offline-sources" (
    nixpkgs.lib.imap0 (i: path: {
      name = toString i;
      path = builtins.storePath path;
    }) sourcePaths
  );
  # Local store mode keeps Nix from asking a daemon outside the network namespace
  # to fetch anything. All installer subprocesses inherit the disconnected netns.
  offlineInstaller = pkgs.writeShellApplication {
    name = "ryoku-install";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux ];
    text = ''
      if [ "$(id -u)" -ne 0 ]; then
        exec /run/wrappers/bin/sudo ${builtins.placeholder "out"}/bin/ryoku-install "$@"
      fi
      exec unshare --net env \
        NIX_REMOTE=local \
        RYOKU_INSTALL_OFFLINE=${sources} \
        RYOKU_INSTALL_TARGET_SOURCE=path:${payloadFlake} \
        RYOKU_INSTALL_TARGET_TRACK=path:${payloadFlake} \
        RYOKU_INSTALL_NIXPKGS_SOURCE=path:${payloadFlake.inputs.nixpkgs} \
        ${startInstaller}/bin/ryoku-start-offline-installer "$@"
    '';
  };
in { inherit iso; }
