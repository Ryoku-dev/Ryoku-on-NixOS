{ pkgs }:

let
  lib = pkgs.lib;

  # ------------------------------------------------------------
  # Toolchain
  #
  # Ryomotion targets Node 22 and pins npm 10.9.4. nixpkgs'
  # Node 22 may carry a newer npm, so keep npm independently
  # pinned while retaining the Nix-native Node runtime.
  # ------------------------------------------------------------

  node = pkgs.nodejs_22;

  electron =
    if pkgs ? electron_43
    then pkgs.electron_43
    else pkgs.electron;

  npmExact = pkgs.stdenvNoCC.mkDerivation {
    pname = "npm";
    version = "10.9.4";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/npm/-/npm-10.9.4.tgz";
      sha256 = "1r2iiwpc6vv89b9v6i6z5byn1sq0gairg7gc4qcls0i3r2haiysb";
    };

    nativeBuildInputs = [
      pkgs.makeWrapper
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/node_modules/npm"
      mkdir -p "$out/bin"

      cp -R . "$out/lib/node_modules/npm/"

      makeWrapper ${node}/bin/node "$out/bin/npm" \
        --add-flags "$out/lib/node_modules/npm/bin/npm-cli.js"

      makeWrapper ${node}/bin/node "$out/bin/npx" \
        --add-flags "$out/lib/node_modules/npm/bin/npx-cli.js"

      runHook postInstall
    '';
  };

  # ------------------------------------------------------------
  # Desktop entry
  # ------------------------------------------------------------

  desktopItem = pkgs.makeDesktopItem {
    name = "ryomotion";
    desktopName = "Ryo Motion";
    genericName = "Screen Demo Editor";

    comment = "Record your screen and turn it into a polished demo";

    exec = "ryomotion %U";
    icon = "ryomotion";

    categories = [
      "AudioVideo"
      "Video"
      "Recorder"
    ];

    startupWMClass = "Ryo Motion";
    terminal = false;
  };

in
pkgs.buildNpmPackage {
  pname = "ryomotion";
  version = "1.5.0";

  src = pkgs.fetchFromGitHub {
    owner = "neur0map";
    repo = "ryomotion";
    rev = "60ea129dabfed8c4936aa6264dc43452c1ed8ab5";
    sha256 = "0jbdj8idwi8mwkny9z4cxy5b6fw4k4i4rm7qy941gv18yp00w7m7";
  };

  nodejs = node;

  # This is the cache hash from Ryomotion's own Nix package at the
  # pinned source revision above.
  npmDepsHash = "sha256-lx38H0qG5IrjQRekLG2N+x90Zq/emPfbxOo/qDSn7iE=";

  makeCacheWritable = true;

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    HUSKY = "0";
  };

  # Electron is supplied by Nix. Native npm install scripts that attempt
  # to download their own Electron build must therefore remain disabled.
  npmFlags = [
    "--ignore-scripts"
  ];

  nativeBuildInputs = [
    npmExact
    pkgs.makeWrapper
    pkgs.copyDesktopItems
  ];

  # ------------------------------------------------------------
  # Patch / dependency phase
  #
  # buildNpmPackage registers its npm configuration as a post-patch
  # hook. Put our exact npm first in PATH before that hook fires.
  # ------------------------------------------------------------

  patchPhase = ''
    runHook prePatch

    export PATH="${npmExact}/bin:${node}/bin:$PATH"

    printf 'Ryomotion Node: '
    node --version

    printf 'Ryomotion npm:  '
    npm --version

    test "$(npm --version)" = "10.9.4"

    substituteInPlace package.json \
      --replace-fail \
        '"name": "ryomotion",' \
        '"name": "ryomotion",
	"productName": "Ryo Motion",'

    # Replace the upstream OpenScreen artwork before Vite copies
    # public/ into the renderer output.
    install -m644 \
      ${../../release/packages/ryomotion/ryomotion-logo.png} \
      public/openscreen.png

    runHook postPatch
  '';

  # ------------------------------------------------------------
  # Build
  #
  # Build the renderer + Electron main/preload code, but deliberately
  # skip electron-builder. The final package runs against Nix's system
  # Electron instead.
  # ------------------------------------------------------------

  buildPhase = ''
    runHook preBuild

    npm run build-vite

    runHook postBuild
  '';

  # ------------------------------------------------------------
  # Installation
  # ------------------------------------------------------------

  installPhase = ''
    runHook preInstall

    app="$out/lib/ryomotion"

    mkdir -p "$app"

    cp -r dist "$app/"
    cp -r dist-electron "$app/"
    cp package.json "$app/"

    # Some main-process paths resolve assets directly from public/
    # when running against system Electron.
    cp -r public "$app/"

    # Electron itself is supplied by Nix, so only retain production
    # JavaScript dependencies in the installed application tree.
    npm prune \
      --omit=dev \
      --no-save \
      --ignore-scripts

    cp -r node_modules "$app/"

    mkdir -p "$out/bin"

    makeWrapper "${electron}/bin/electron" "$out/bin/ryomotion" \
      --add-flags "$app" \
      --set ELECTRON_IS_DEV 0 \
      --prefix PATH : "${
        lib.makeBinPath [
          pkgs.gpu-screen-recorder
          pkgs.xdg-utils
        ]
      }"

    # The Ryoku package intentionally uses the same mark at every
    # hicolor size, matching the existing Arch package.
    for size in 16 32 48 64 128 256 512 1024; do
      install -Dm644 \
        ${../../release/packages/ryomotion/ryomotion-logo.png} \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/ryomotion.png"
    done

    runHook postInstall
  '';

  desktopItems = [
    desktopItem
  ];

  meta = {
    description = "Ryo Motion screen-demo recorder and editor";
    homepage = "https://github.com/neur0map/ryomotion";
    license = lib.licenses.mit;

    mainProgram = "ryomotion";

    platforms = [
      "x86_64-linux"
    ];
  };
}
