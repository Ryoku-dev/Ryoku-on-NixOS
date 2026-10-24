{
  pkgs,
  src,
  desktopData,
}:

let
  repoSrc = src;

  runtimePath = pkgs.lib.makeBinPath [
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.findutils
    pkgs.gawk
    pkgs.gnugrep
    pkgs.gnused
    pkgs.iproute2
    pkgs.jq
    pkgs.nix
    pkgs.pciutils
    pkgs.procps
    pkgs.systemd
    pkgs.util-linux
    pkgs.which
  ];
in
pkgs.stdenv.mkDerivation {
  pname = "ryoku-rashin";
  version = "unstable";

  src = repoSrc + "/ryoku/rashin/backend";

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

    go build \
      -mod=vendor \
      -trimpath \
      -o ryoku-rashin \
      .

    ./ryoku-rashin \
      repo-index \
      "${repoSrc}" \
      "$TMPDIR/ryoku-repo.md"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/libexec" \
      "$out/share/ryoku/rashin/wiki" \
      "$out/share/ryoku/skills"

    install -Dm755 \
      ryoku-rashin \
      "$out/libexec/ryoku-rashin"

    install -Dm644 \
      "$TMPDIR/ryoku-repo.md" \
      "$out/share/ryoku/rashin/ryoku-repo.md"

    cp -a \
      "${repoSrc}/ryoku/rashin/skills/." \
      "$out/share/ryoku/skills/"

    cp -a \
      "${repoSrc}/ryoku/rashin/wiki/." \
      "$out/share/ryoku/rashin/wiki/"

    makeWrapper \
      "$out/libexec/ryoku-rashin" \
      "$out/bin/ryoku-rashin" \
      --set RYOKU_PACKAGE_BACKEND nix \
      --set RYOKU_RASHIN_NIXOS 1 \
      --set RYOKU_CONFIG_BASE "${desktopData}/share/ryoku/config" \
      --set RYOKU_RASHIN_SHIPPED "$out/share/ryoku/rashin/ryoku-repo.md" \
      --set RYOKU_RASHIN_WIKI "$out/share/ryoku/rashin/wiki" \
      --prefix PATH : "${runtimePath}"

    ln -s ryoku-rashin "$out/bin/rashin"

    runHook postInstall
  '';

  meta = {
    description = "Ryoku Rashin local agent OS daemon and dashboard";
    homepage = "https://github.com/Ryoku-dev/ryoku-arch";
    license = pkgs.lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
