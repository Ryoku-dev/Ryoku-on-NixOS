{ pkgs, src }:

pkgs.stdenv.mkDerivation {
  pname = "ryoku-palette-bridge";
  version = "unstable";

  src = builtins.path {
    path = src + "/ryoku/palette-bridge";
    name = "ryoku-palette-bridge-source";
  };

  nativeBuildInputs = [
    pkgs.go
    pkgs.makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    export GOCACHE="$TMPDIR/go-cache"
    export GOTOOLCHAIN=local
    export CGO_ENABLED=0

    go test ./...

    go build \
      -trimpath \
      -ldflags="-s -w" \
      -o "$TMPDIR/ryoku-palette-bridge" \
      .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/libexec" \
      "$out/share/ryoku/palette-bridge"

    install -Dm755 \
      "$TMPDIR/ryoku-palette-bridge" \
      "$out/bin/ryoku-palette-bridge"

    # Keep the integration payload available to Ryogami/Hub from one immutable
    # source tree. The app integration scripts intentionally remain user-state
    # operations; only package/service installation is Nix-owned.
    cp -a ./. "$out/share/ryoku/palette-bridge/"

    # Upstream install.sh builds into ~/.local/bin and writes a mutable user
    # systemd unit. NixOS owns both pieces declaratively, so retain the file as
    # the UI's source-ready contract while making the action safe and truthful.
    cat > "$out/share/ryoku/palette-bridge/install.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  'Ryoku Palette Bridge is managed by NixOS.' \
  'Update/switch the Ryoku NixOS generation to update the bridge package.'
SH

    patchShebangs "$out/share/ryoku/palette-bridge"

    install -Dm755 \
      "$out/share/ryoku/palette-bridge/doctor.sh" \
      "$out/libexec/ryoku-palette-bridge-doctor"

    install -Dm755 \
      "$out/share/ryoku/palette-bridge/remove-integrations.sh" \
      "$out/libexec/ryoku-palette-bridge-remove-integrations"

    makeWrapper \
      "$out/libexec/ryoku-palette-bridge-doctor" \
      "$out/bin/ryoku-palette-bridge-doctor" \
      --prefix PATH : "${pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
        pkgs.systemd
      ]}"

    makeWrapper \
      "$out/libexec/ryoku-palette-bridge-remove-integrations" \
      "$out/bin/ryoku-palette-bridge-remove-integrations" \
      --prefix PATH : "${pkgs.lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
      ]}"

    runHook postInstall
  '';

  meta = {
    description =
      "Ryoku wallpaper palette event bridge and app integration payload";
    homepage =
      "https://github.com/Ryoku-dev/ryoku";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
