# One desktop profile, one kernel. Firmware variants share the same packages.
{ pkgs, mkSystem, includeNvidia ? false }:
let
  make = firmware: (mkSystem {
    inherit firmware;
    kernel = "latest";
    compositor = "niri";
    browser = "firefox";
    optionalApps = [ ];
    minimal = true;
    gpuVendors = [ "amd" "intel" ] ++ pkgs.lib.optional includeNvidia "nvidia";
  }).extendModules {
    modules = [
      ./profile.nix
      {
        hardware.cpu.amd.updateMicrocode = true;
        hardware.cpu.intel.updateMicrocode = true;
        hardware.enableRedistributableFirmware = true;
      }
    ];
  };
  configurations = { uefi = make "uefi"; bios = make "bios"; };
  systems = map (s: s.config.system.build.toplevel) (builtins.attrValues configurations);
  # Only the tools used to generate machine-specific configuration/initrds.
  # Desktop applications are already built; do not ship language toolchains.
  toolsFor = p: with p; [
    stdenvNoCC bash coreutils coreutils-full coreutils-full.info findutils gnugrep gnused gawk
    gnutar gzip bzip2 xz zstd cpio rsync jq perl python3 makeWrapper
    util-linux e2fsprogs dosfstools btrfs-progs (lib.getBin kmod) kmod.dev kmod.man systemd
    # Prebuilt helpers for security wrappers, D-Bus XML and system links.
    # These build-time tools are absent from the installed runtime closure.
    libcap-text-verifier libxslt.bin lndir texinfo
  ];
  tools = pkgs.lib.concatMap toolsFor [ pkgs (make "uefi").pkgs ];
in
(pkgs.linkFarm "ryoku-offline-payload" (
  pkgs.lib.imap0 (i: path: { name = "system-${toString i}"; inherit path; }) systems
  ++ pkgs.lib.imap0 (i: path: { name = "tool-${toString i}"; inherit path; }) tools
)).overrideAttrs (_: { passthru = { inherit configurations; buildTools = tools; }; })
