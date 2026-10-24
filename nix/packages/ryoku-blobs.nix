{ pkgs, src, qmlRoot }:

pkgs.stdenv.mkDerivation {
  pname = "ryoku-blobs";
  version = "unstable";

  dontWrapQtApps = true;

  src = src + "/ryoku/shell/plugin";

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    pkgs.qt6.qtshadertools
  ];

  buildInputs = [
    pkgs.qt6.qtbase
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qtmultimedia
    pkgs.qt6.qtquick3d
    pkgs.qt6.qtshadertools
  ];

  preConfigure = ''
    rm -rf build
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/${qmlRoot}/Ryoku"

    for module in Blobs Spatial3D; do
      cp -a "qml/Ryoku/$module" "$out/${qmlRoot}/Ryoku/$module"
      rm -f "$out/${qmlRoot}/Ryoku/$module/"*.qrc
    done

    runHook postInstall
  '';

  meta = {
    description = "Ryoku.Blobs metaball and Ryoku.Spatial3D depth-mesh Qt/QML modules";
    homepage = "https://github.com/Ryoku-dev/ryoku-arch";
    license = pkgs.lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };
}
