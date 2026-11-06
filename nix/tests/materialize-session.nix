# Behavioural check of ryoku-materialize and its best-effort session wrapper.
#
# The real materializer script is built against stub Ryoku tools, so the
# locking, atomic-replacement and failure-handling logic runs for real without
# pulling in the desktop packages.
{ pkgs, self }:

let
  stub = name: body: pkgs.writeShellScriptBin name body;

  desktopData = pkgs.runCommand "stub-desktop-data" { } ''
    cfg=$out/share/ryoku/config
    mkdir -p $cfg/niri $cfg/hypr $cfg/mango $out/share/ryoku/wallpapers
    echo 'include "autostart.kdl"' > $cfg/niri/config.kdl
    echo '// autostart' > $cfg/niri/autostart.kdl
    chmod 0444 $cfg/niri/*
  '';

  qml = pkgs.runCommand "stub-qml" { } ''
    for m in Ui PluginKit FrameBars Blobs Wm; do
      mkdir -p $out/lib/qt-6/qml/Ryoku/$m
    done
  '';

  # `ryoku materialize` seeds user files only when absent; it fails on request.
  cli = pkgs.symlinkJoin {
    name = "stub-cli";
    paths = [
      (stub "ryoku" ''
        case "$1" in
          materialize)
            [ -z "''${RYOKU_STUB_FAIL:-}" ] || { echo "stub: materialize failed" >&2; exit 3; }
            mkdir -p "$XDG_CONFIG_HOME/niri" "$XDG_CONFIG_HOME/ryoku"
            [ -e "$XDG_CONFIG_HOME/niri/user.kdl" ] || echo '// seed' > "$XDG_CONFIG_HOME/niri/user.kdl"
            sleep 0.05
            ;;
        esac
      '')
    ];
  };

  wm = name: pkgs.symlinkJoin {
    name = "stub-${name}";
    paths = [ (stub name "exit 0") ];
  };

  materialize = import (self + "/nix/apps/ryoku-materialize.nix") {
    inherit pkgs;
    ryoku = {
      inherit desktopData qml cli;
      hub = pkgs.emptyDirectory;
      wmHyprland = wm "ryoku-wm-hyprland";
      wmNiri = wm "ryoku-wm-niri";
      wmMango = wm "ryoku-wm-mango";
    };
  };

  bestEffort = pkgs.writeShellScript "ryoku-materialize-best-effort"
    (builtins.replaceStrings
      [ "#!/usr/bin/env bash\n" "@materializer@" "@coreutils@" ]
      [ "" "${materialize}/bin/ryoku-materialize" "${pkgs.coreutils}/bin" ]
      (builtins.readFile (self + "/nix/scripts/ryoku-materialize-best-effort")));
in
pkgs.runCommand "ryoku-materialize-session-check"
  { nativeBuildInputs = [ pkgs.coreutils pkgs.findutils pkgs.gnugrep ]; }
  ''
    MATERIALIZE=${materialize}/bin/ryoku-materialize \
    BEST_EFFORT=${bestEffort} \
      bash ${self + "/nix/tests/test-materialize-session.sh"}
    touch "$out"
  ''
