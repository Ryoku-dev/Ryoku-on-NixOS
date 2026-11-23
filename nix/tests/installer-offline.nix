{ pkgs }:
let
  testSystem = pkgs.runCommand "offline-installer-test-system" { } ''
    mkdir -p "$out/bin"
    touch "$out/bin/switch-to-configuration"
    chmod +x "$out/bin/switch-to-configuration"
  '';
in
pkgs.runCommand "ryoku-installer-offline-check" {
  nativeBuildInputs = with pkgs; [ bash coreutils gawk gnugrep python3 ];
} ''
  export RYOKU_INSTALL_BACKEND_SOURCE=${../apps/ryoku-install-backend.sh}
  export RYOKU_INSTALL_OFFLINE_HELPER=${../iso/offline/install.sh}
  export RYOKU_INSTALL_TEST_SYSTEM=${testSystem}
  bash ${./test-installer-offline.sh}
  export RYOKU_OFFLINE_BUILDER_SOURCE=${../iso/offline/build.sh}
  python3 ${./test-offline-iso-builder.py}
  touch "$out"
''
