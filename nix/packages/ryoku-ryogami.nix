{
  pkgs,
  src,
  livewall,
  waifu2x,
  qmlRoot,
  paletteBridge,
}:

let
  waifu2xModels =
    "${waifu2x}/share/waifu2x-ncnn-vulkan/models-cunet";

  runtimePath = pkgs.lib.makeBinPath [
    pkgs.coreutils
    pkgs.procps

    pkgs.ffmpeg
    pkgs.imagemagick
    pkgs.matugen

    pkgs.curl
    pkgs.inotify-tools

    pkgs.quickshell

    waifu2x
  ];
in

pkgs.stdenv.mkDerivation {
  pname = "ryoku-ryogami";
  version = "unstable";

  src = src + "/ryoku/shell/ryogami";

  dontWrapQtApps = true;
  dontConfigure = true;

  nativeBuildInputs = [
    pkgs.go
    pkgs.makeWrapper

    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config

    pkgs.qt6.qtshadertools
  ];

  buildInputs = [
    pkgs.qt6.qtbase
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qtmultimedia
    pkgs.qt6.qtshadertools

    pkgs.wayland
    pkgs.wayland-protocols
    pkgs.vulkan-headers
  ];

  postPatch = ''
    # Upstream packages waifu2x models below /usr/share. NixOS keeps them
    # inside Ryoku's immutable waifu2x derivation.
    substituteInPlace daemon/upscale.go \
      --replace-fail \
        '/usr/share/waifu2x-ncnn-vulkan/models-cunet' \
        '${waifu2xModels}'

    # The palette integration recipes live in the palette-bridge package.
    substituteInPlace daemon/palette_bridge.go \
      --replace-fail \
        '"/usr/share/ryoku/palette-bridge"' \
        '"${paletteBridge}/share/ryoku/palette-bridge"'

    install -Dm644 \
      ${src}/ryoku/assets/brand/logo-mark-v2.png \
      picker/logo-mark-v2.png

    substituteInPlace picker/CMakeLists.txt \
      --replace-fail \
        '../../../assets/brand/logo-mark-v2.png' \
        'logo-mark-v2.png'

  '';

  buildPhase = ''
    runHook preBuild

    root="$PWD"

    # ── Ryogami daemon ──────────────────────────────────────

    cd daemon

    export HOME="$TMPDIR"
    export GOCACHE="$TMPDIR/go-cache"
    export GOTOOLCHAIN=local
    export CGO_ENABLED=0

    # Ryogami's ordinary tests exercise the same external image/video
    # helpers as the runtime. Make the declared runtime closure available
    # inside the Nix build sandbox as well.
    export PATH="${runtimePath}:$PATH"

    # The E2E suite launches another daemon inside the build sandbox.
    # Ordinary package tests still run here.
    go test -skip '^TestE2E' ./...

    go build \
      -trimpath \
      -o ryogami \
      .

    cd "$root"

    # ── Ryogami 0.78 picker ────────────────────────────────
    #
    # Upstream replaced the previous pure-QML picker with Ryoku.Ryogami:
    # a compiled Qt Quick module containing the C++ GPU card renderer,
    # shaders and the new picker QML surface.

    cmake \
      -S picker \
      -B picker-build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release

    cmake --build picker-build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/share/ryogami" \
      "$out/share/applications" \
      "$out/share/licenses/ryogami" \
      "$out/${qmlRoot}/Ryoku"

    install -Dm755 \
      daemon/ryogami \
      "$out/bin/ryogami"

    # Ryogami expects this executable name. Reuse Ryoku's existing
    # Nix-built live wallpaper renderer.
    ln -s \
      "${livewall}/bin/ryoku-livewall" \
      "$out/bin/ryogami-live"

    # Compiled Ryoku.Ryogami QML module.
    cp -a \
      picker-build/qml/Ryoku/Ryogami \
      "$out/${qmlRoot}/Ryoku/Ryogami"

    rm -f \
      "$out/${qmlRoot}/Ryoku/Ryogami/"*.qrc

    # The daemon launches this through Quickshell. The actual implementation
    # resolves from the Ryoku.Ryogami QML module above.
    install -Dm644 \
      picker/shell.qml \
      "$out/share/ryogami/shell.qml"

    install -Dm644 \
      picker/data/ryogami.desktop \
      "$out/share/applications/ryogami.desktop"

    install -Dm644 \
      picker/LICENSE \
      "$out/share/licenses/ryogami/LICENSE"

    install -Dm644 \
      picker/NOTICE \
      "$out/share/licenses/ryogami/NOTICE"

    for license in picker/qml/theme/fonts/*.txt; do
      install -Dm644 \
        "$license" \
        "$out/share/licenses/ryogami/$(basename "$license")"
    done

    # process.go still has /usr/share/ryogami as its generic packaged
    # fallback. The Nix wrapper supplies the immutable store entry point.
    #
    # QML_IMPORT_PATH is also prefixed here so a directly launched daemon
    # can resolve its compiled Ryoku.Ryogami module even outside the
    # declarative systemd unit.
    wrapProgram "$out/bin/ryogami" \
      --set RYOGAMI_SHELL_QML "$out/share/ryogami/shell.qml" \
      --prefix QML_IMPORT_PATH : "$out/${qmlRoot}" \
      --prefix QML2_IMPORT_PATH : "$out/${qmlRoot}" \
      --prefix QT_PLUGIN_PATH : "${pkgs.qt6.qtimageformats}/lib/qt-6/plugins:${pkgs.qt6.qtbase}/lib/qt-6/plugins" \
      --prefix PATH : "$out/bin:${runtimePath}"

    runHook postInstall
  '';

  meta = {
    description =
      "Ryogami wallpaper daemon and Qt Quick picker for Ryoku";
    homepage =
      "https://github.com/Ryoku-dev/ryoku";
    license = pkgs.lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
