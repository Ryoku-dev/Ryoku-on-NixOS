{ pkgs, src, nixosSystemBridge }:

let
  # polkit is a multi-output package:
  #   bin -> pkexec and CLI tools
  #   out -> daemon, systemd units and polkit-agent-helper-1
  polkitOut = pkgs.lib.getOutput "out" pkgs.polkit;
in

pkgs.stdenv.mkDerivation {
  pname = "ryoku-shell";
  version = "unstable";

  src = src + "/ryoku/shell/ipc";

  nativeBuildInputs = [
    pkgs.go
  ];

  postPatch = ''
    # Fail the Nix build immediately if nixpkgs ever moves this helper.
    test -x \
      "${polkitOut}/lib/polkit-1/polkit-agent-helper-1"

    # Upstream targets the normal Arch/FHS location. NixOS keeps the
    # helper inside polkit's immutable `out` output instead.
    substituteInPlace polkit.go \
      --replace-fail \
        'var polkitHelperPath = "/usr/lib/polkit-1/polkit-agent-helper-1"' \
        'var polkitHelperPath = "${polkitOut}/lib/polkit-1/polkit-agent-helper-1"'

    # /usr/bin/ryoku-dns does not exist on NixOS, and the fallback beside this
    # binary does not either. Run the bridge's store path, which is the exact
    # program the NixOS polkit rule authorizes.
    substituteInPlace network.go \
      --replace-fail \
        'var dnsPackagedHelper = "/usr/bin/ryoku-dns"' \
        'var dnsPackagedHelper = "${nixosSystemBridge}/bin/ryoku-dns"'
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    export GOCACHE="$TMPDIR/go-cache"
    export GOTOOLCHAIN=local

    go build \
      -mod=vendor \
      -trimpath \
      -o ryoku-shell \
      .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    install -Dm755 ryoku-shell "$out/bin/ryoku-shell"

    runHook postInstall
  '';

  meta = {
    description = "Ryoku desktop shell IPC daemon";
    homepage = "https://github.com/Ryoku-dev/ryoku-arch";
    license = pkgs.lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
