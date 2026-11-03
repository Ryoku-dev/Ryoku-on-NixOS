{ pkgs, src, ryokuTokens ? ../../ryoku/ui/Singletons/Tokens.qml }:
let
  upstream = import (src + "/nix/package.nix") { inherit pkgs; };
in upstream.overrideAttrs (old: {
  pname = "ryoku-shima";
  postPatch = (old.postPatch or "") + ''
    python3 ${./shima/host-patch.py} . ${./shima/ShellBridge.qmlfrag} ${./shima/RyokuHost.qml} ${./shima/PolkitServiceImpl.qml} ${./shima/Lock.qml} ${ryokuTokens}
    python3 ${./shima/appearance-controls.py} .
    python3 ${./shima/visualizer-palette-patch.py} . ${./shima/RyokuVisualizerPalette.qml}
    patch -p1 --fuzz=0 < ${./shima/interaction-fixes.patch}
  '';
  postInstall = (old.postInstall or "") + ''
    rm "$out/bin/inir"
    install -Dm644 ${./shima/launcher.py} "$out/libexec/shima/launcher.py"
    install -Dm644 ${./shima/wallpaper.py} "$out/libexec/shima/wallpaper.py"
    cp LICENSE "$out/share/quickshell/inir/LICENSE"
    mkdir -p "$out/share/doc/ryoku-shima"
    cp ${./shima/NOTICE} "$out/share/doc/ryoku-shima/NOTICE"
    makeWrapper ${pkgs.python3}/bin/python3 "$out/bin/ryoku-shima" \
      --add-flags "$out/libexec/shima/launcher.py" \
      --set RYOKU_SHIMA_SOURCE "$out/share/quickshell/inir" \
      --prefix PATH : "${pkgs.lib.makeBinPath old.passthru.runtimeDependencies}:$out/bin" \
      --prefix QML2_IMPORT_PATH : "${pkgs.lib.makeSearchPath "lib/qt-6/qml" [
        pkgs.qt6.qt5compat pkgs.qt6.qtmultimedia
        pkgs.kdePackages.kirigami.unwrapped pkgs.kdePackages.syntax-highlighting
      ]}" \
      --prefix QT_PLUGIN_PATH : "${pkgs.lib.makeSearchPath "lib/qt-6/plugins" [ pkgs.qt6.qtmultimedia pkgs.qt6.qtimageformats ]}" \
      --set FONTCONFIG_FILE "${pkgs.makeFontsConf { fontDirectories = [ pkgs.material-symbols pkgs.rubik ]; }}"
    makeWrapper ${pkgs.python3}/bin/python3 "$out/bin/ryoku-shima-wallpaper" \
      --add-flags "$out/libexec/shima/wallpaper.py"
  '';
  meta = old.meta // {
    description = "Upstream iNiR runtime for the managed Ryoku Shima subshell";
    mainProgram = "ryoku-shima";
  };
})
