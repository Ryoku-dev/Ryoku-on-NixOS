{
  pkgs,
  ryomanagerSrc,
}:

pkgs.buildGoModule rec {
  pname = "ryomanager";
  version = "0.1.0";

  src = ryomanagerSrc;

  vendorHash = "sha256-HOfeloECZ4bWUmKDwCUjnXFtmf6MyflELEhjZ4BScNQ=";

  # buildGoModule's default vendoring (`go mod vendor`) has to successfully
  # *load* every package in the main module to know which deps are
  # directly used. Loading main.go here fails: its `go:embed
  # all:frontend/dist` has nothing to embed (npm hasn't run), and the
  # vendoring derivation never gets gtk3/webkitgtk (only `buildInputs` on
  # the main derivation, not propagated to the separate goModules FOD) for
  # wails' cgo-based webview package. Either failure silently drops
  # main.go and its real imports (echo, wails, mattn/*, ...) from
  # consideration, leaving vendor/modules.txt empty even though go.mod
  # correctly lists them as required -- exactly the
  # "explicitly required in go.mod, but not marked as explicit in
  # vendor/modules.txt" error. proxyVendor sidesteps all of this: instead
  # of scanning imports, it mirrors every module in go.sum into a local
  # GOPROXY cache, so the real build resolves modules normally (-mod=mod)
  # instead of being checked against a vendor snapshot.
  proxyVendor = true;

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
