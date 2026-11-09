{ pkgs, src, upstreamQml }:

let
  qmlRoot = "lib/qt-6/qml";

  blobsWithText = (import (src + "/nix/packages/ryoku-blobs.nix") {
    inherit pkgs src qmlRoot;
  }).overrideAttrs (old: {
    installPhase = old.installPhase + ''
      cp -a qml/Ryoku/Text "$out/${qmlRoot}/Ryoku/"
      rm -f "$out/${qmlRoot}/Ryoku/Text/"*.qrc
    '';
  });
in
pkgs.runCommand "ryoku-hyperion-qml-runtime" { } ''
  cp -a ${upstreamQml}/. "$out/"
  chmod u+w "$out/${qmlRoot}/Ryoku" "$out/${qmlRoot}/Ryoku/Ui" "$out/${qmlRoot}/Ryoku/Ui/Singletons"

  mkdir -p "$out/${qmlRoot}/Ryoku/Ui/lib"
  cp -a ${src}/ryoku/ui/lib/*.js "$out/${qmlRoot}/Ryoku/Ui/lib/"
  cp -a ${src}/ryoku/ui/Singletons/*.js "$out/${qmlRoot}/Ryoku/Ui/Singletons/"

  cp -a ${blobsWithText}/${qmlRoot}/Ryoku/Text "$out/${qmlRoot}/Ryoku/"

  test -f "$out/${qmlRoot}/Ryoku/Ui/lib/spectrum.js"
  test -f "$out/${qmlRoot}/Ryoku/Ui/Singletons/buspath.js"
  test -f "$out/${qmlRoot}/Ryoku/Text/qmldir"
''
