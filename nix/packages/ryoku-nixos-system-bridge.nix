{ pkgs, src }:

let
  runtimePath = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    (pkgs.lib.getBin pkgs.glibc)

    pkgs.networkmanager
    pkgs.iw
    pkgs.systemd
    pkgs.python3

    pkgs.docker
  ];

  # Privileged commands owned by this bridge. Other Ryoku packages must not
  # ship executables with these names; ryoku-helpers drops its Arch copies.
  commands = [
    "ryoku-dns"
    "ryoku-wifi-backend"
    "ryoku-wifi-regdom"
    "ryoku-docker"
    "ryoku-sddm-session"
  ];
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "ryoku-nixos-system-bridge";
  version = "unstable";

  src = src + "/nix/bridge";

  dontBuild = true;

  passthru = { inherit commands; };

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"

    for helper in ${pkgs.lib.escapeShellArgs commands}
    do
      install -Dm755 \
        "$helper" \
        "$out/bin/$helper"

      substituteInPlace \
        "$out/bin/$helper" \
        --replace-fail \
          "@RYOKU_RUNTIME_PATH@" \
          "${runtimePath}"
    done

    patchShebangs "$out/bin"

    runHook postInstall
  '';

  meta = {
    description =
      "NixOS-native privileged system bridges used by Ryoku";

    homepage =
      "https://github.com/Ryoku-dev/ryoku-arch";

    license = pkgs.lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
