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

  # Stubs for the retry script: the live run clears the marker unless told to
  # keep failing, and session start / systemctl just record that they ran.
  stubLive = pkgs.writeShellScript "stub-live" ''
    [ -z "''${RYOKU_STUB_KEEP_FAILING:-}" ] || exit 0
    rm -f "$XDG_STATE_HOME/ryoku/nix/materialize-failed"
    echo live >> "$RYOKU_STUB_LOG"
  '';
  stubSessionStart = pkgs.writeShellScript "stub-session-start" ''
    echo session-start >> "$RYOKU_STUB_LOG"
  '';
  stubSystemctl = pkgs.writeShellScript "stub-systemctl" ''
    [ -n "''${RYOKU_STUB_TARGET_ACTIVE:-}" ]
  '';
  retry = pkgs.writeShellScript "ryoku-materialize-retry"
    (builtins.replaceStrings
      [ "#!/usr/bin/env bash\n" "@materializeLive@" "@sessionStart@" "@systemctl@" ]
      [ "" "${stubLive}" "${stubSessionStart}" "${stubSystemctl}" ]
      (builtins.readFile (self + "/nix/scripts/ryoku-materialize-retry")));
in
pkgs.runCommand "ryoku-materialize-session-check"
  { nativeBuildInputs = [ pkgs.coreutils pkgs.findutils pkgs.gnugrep ]; }
  ''
    MATERIALIZE=${materialize}/bin/ryoku-materialize \
    BEST_EFFORT=${bestEffort} \
    RETRY=${retry} \
      bash ${self + "/nix/tests/test-materialize-session.sh"}
    touch "$out"
  ''
