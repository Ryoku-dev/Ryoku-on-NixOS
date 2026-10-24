{
  pkgs,
  ryomanagerSrc,
}:

pkgs.buildGoModule rec {
  pname = "ryomanager";
  version = "0.1.0";

  src = ryomanagerSrc;

  vendorHash = "sha256-wmLUsQlA705xwX1WAgmsA4pQiAqA3Esa/0EoB8GASbo=";

  npmRoot = "frontend";
  npmDeps = pkgs.fetchNpmDeps {
    src = "${src}/frontend";
    hash = "sha256-Y+g6mhmRwPxSx2RkjXqAiAED74APQw6161bFkNiH6LU=";
  };

  nativeBuildInputs = [
    pkgs.nodejs
    pkgs.npmHooks.npmConfigHook
    pkgs.pkg-config
    pkgs.wrapGAppsHook3
  ];

  buildInputs = [
    pkgs.gtk3
    pkgs.webkitgtk_4_1
  ];

  tags = [ "desktop" "production" "webkit2_41" ];

  overrideModAttrs = oldAttrs: {
    nativeBuildInputs = pkgs.lib.filter (drv: drv != pkgs.npmHooks.npmConfigHook) oldAttrs.nativeBuildInputs;
    preBuild = "";
  };

  preBuild = ''
    export HOME="$TMPDIR"
    pushd frontend >/dev/null
    npm run build
    popd >/dev/null
    test -f frontend/dist/index.html
  '';

  doCheck = false;

  postInstall = ''
    install -Dm644 \
      build/appicon.png \
      "$out/share/icons/hicolor/512x512/apps/ryomanager.png"

    install -Dm644 /dev/stdin "$out/share/applications/ryomanager.desktop" <<'DESKTOP'
[Desktop Entry]
Name=RyoManager
Comment=Ryoku system task manager
Exec=ryomanager
Icon=ryomanager
Terminal=false
Type=Application
Categories=System;Monitor;
StartupWMClass=ryomanager
DESKTOP
  '';

  meta = {
    description = "Ryoku-native system task manager";
    homepage = "https://github.com/Ryoku-dev/ryomanager";
    license = pkgs.lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ryomanager";
  };
}
