{ pkgs, backend }:

pkgs.buildGo126Module {
  pname = "ryoku-install";
  version = "unstable";

  src = ../installer/tui;

  vendorHash = "sha256-xWBwrvVVKSCtUi3v3AmVOcFeBz4cwKFwI3tKUNHXnUc=";

  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    if [ -x "$out/bin/ryoku-nix-installer" ]; then
      mv "$out/bin/ryoku-nix-installer" "$out/bin/ryoku-install"
    elif [ ! -x "$out/bin/ryoku-install" ]; then
      echo "ryoku-install: Go build did not produce the expected installer binary" >&2
      exit 1
    fi

    wrapProgram "$out/bin/ryoku-install" \
      --set RYOKU_INSTALL_BACKEND "${backend}/bin/ryoku-install-backend" \
      --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.networkmanager pkgs.util-linux pkgs.whois ]}"
  '';

  meta = {
    description = "Ryoku's interactive NixOS installer";
    mainProgram = "ryoku-install";
    platforms = pkgs.lib.platforms.linux;
  };
}
