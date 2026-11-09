# Ryotunes as Ryoku Hyperion ships it on Arch: the official Ryoku-dev/ryotunes
# release (release/repo/import-ryotunes.sh imports releases/latest, unpatched)
# with the same files as that package: ryotunes (launcher), ryotunesd (daemon,
# socket-activated user unit), ryotunes-qml (native Quickshell client),
# ryotunes-cli, ryotunes-sync, the desktop entry, skins and matugen template.
#
# NixOS differences, all about ownership:
# - The launcher starts its own daemon and the daemon spawns its own client by
#   store path, never through PATH, so an older ryotunes elsewhere on PATH
#   (RyoMarket profiles, ~/.local/bin) cannot take over a session.
# - The client gets Hyperion's QML runtime (Ryoku.Ui) instead of /usr/lib/qt6.
# - The in-app pacman updater is inert (no /usr/bin/pacman); NixOS updates it.
{ pkgs, src, version, qmlRuntime }:

let
  inherit (pkgs) lib;

  qmlImports = lib.makeSearchPath "lib/qt-6/qml" [
    qmlRuntime
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qtmultimedia
    pkgs.qt6.qtwayland
    pkgs.qt6.qt5compat
    pkgs.qt6.qtsvg
    pkgs.qt6.qtimageformats
  ];

  # Tools the official package depends on and the daemon runs by name.
  daemonPath = lib.makeBinPath [
    pkgs.yt-dlp
    pkgs.ffmpeg
    pkgs.xdg-utils
  ];
in
pkgs.rustPlatform.buildRustPackage {
  pname = "ryotunes";
  inherit version src;

  cargoHash = "sha256-quUL+BEGdNnQ9/RsU3/bK+vYLLvqsTFGOD92GSdC3jc=";

  pnpmDeps = pkgs.fetchPnpmDeps {
    pname = "ryotunes-ui";
    inherit version;
    src = src + "/ui";
    fetcherVersion = 4;
    hash = "sha256-L0HRYhFO5A0qqwdiYzN+h28kV7vAqB3up+Zu4ShYnBo=";
  };
  pnpmRoot = "ui";

  postPatch = ''
    substituteInPlace crates/ryotunesd/src/tray.rs \
      --replace-fail 'Command::new("ryotunes-qml")' "Command::new(\"$out/bin/ryotunes-qml\")"
    substituteInPlace src-tauri/src/main.rs \
      --replace-fail 'Command::new("ryotunesd")' "Command::new(\"$out/bin/ryotunesd\")"
  '';

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.nodejs
    pkgs.pnpm
    pkgs.pnpmConfigHook
    pkgs.wrapGAppsHook3
    pkgs.makeWrapper
    pkgs.rustPlatform.bindgenHook
  ];

  buildInputs = [
    pkgs.glib
    pkgs.gtk3
    pkgs.gdk-pixbuf
    pkgs.cairo
    pkgs.pango
    pkgs.webkitgtk_4_1
    pkgs.libsoup_3
    pkgs.mpv
    pkgs.libappindicator-gtk3
    pkgs.libayatana-appindicator
    pkgs.openssl
    pkgs.librsvg
  ];

  # The Tauri crate embeds the Svelte build even though Linux never runs it.
  preBuild = ''
    export HOME="$TMPDIR"
    (cd ui && pnpm build)
    test -f ui/build/index.html
  '';

  cargoBuildFlags = [
    "--package" "ryotunes"
    "--package" "sync-server"
    "--package" "ryotunesd"
    "--package" "ryotunes-cli"
  ];

  # Upstream runs the workspace tests at release time.
  doCheck = false;

  installPhase = ''
    runHook preInstall

    for bin in ryotunes ryotunes-sync ryotunesd ryotunes-cli; do
      built="$(find target -type f -path "*/release/$bin" -perm -0100 -print -quit)"
      [ -n "$built" ] || { echo "ryotunes: built binary missing: $bin" >&2; exit 1; }
      install -Dm755 "$built" "$out/bin/$bin"
    done
    install -Dm755 scripts/diagnostics.sh "$out/bin/ryotunes-diagnostics"

    mkdir -p "$out/share/ryotunes"
    cp -r client "$out/share/ryotunes/client"
    rm -rf "$out/share/ryotunes/client/tests"
    cp -r skins "$out/share/ryotunes/skins"
    install -Dm644 matugen/ryotunes.json "$out/share/ryotunes/matugen/ryotunes.json"

    install -Dm644 packaging/linux/ryotunesd.socket "$out/lib/systemd/user/ryotunesd.socket"
    install -Dm644 packaging/linux/ryotunesd.service "$out/lib/systemd/user/ryotunesd.service"
    substituteInPlace "$out/lib/systemd/user/ryotunesd.service" \
      --replace-fail "ExecStart=/usr/bin/ryotunesd" "ExecStart=$out/bin/ryotunesd"

    install -Dm644 packaging/linux/ryotunes.desktop "$out/share/applications/ryotunes.desktop"
    substituteInPlace "$out/share/applications/ryotunes.desktop" \
      --replace-fail "Exec=ryotunes" "Exec=$out/bin/ryotunes"
    install -Dm644 packaging/linux/dev.ryoku.ryotunes.metainfo.xml \
      "$out/share/metainfo/dev.ryoku.ryotunes.metainfo.xml"

    install -Dm644 src-tauri/icons/32x32.png "$out/share/icons/hicolor/32x32/apps/ryotunes.png"
    install -Dm644 src-tauri/icons/64x64.png "$out/share/icons/hicolor/64x64/apps/ryotunes.png"
    install -Dm644 src-tauri/icons/128x128.png "$out/share/icons/hicolor/128x128/apps/ryotunes.png"
    install -Dm644 "src-tauri/icons/128x128@2x.png" "$out/share/icons/hicolor/256x256/apps/ryotunes.png"
    install -Dm644 src-tauri/icons/icon.png "$out/share/icons/hicolor/512x512/apps/ryotunes.png"

    install -Dm644 LICENSE "$out/share/licenses/ryotunes/LICENSE"

    runHook postInstall
  '';

  # wrapGAppsHook3 wraps bin/ in fixupPhase; the client wrapper is written
  # afterwards so it is not wrapped twice.
  dontWrapGApps = true;
  postFixup = ''
    for bin in ryotunes ryotunesd ryotunes-cli ryotunes-sync; do
      wrapProgram "$out/bin/$bin" "''${gappsWrapperArgs[@]}" --prefix PATH : ${daemonPath}
    done
    makeWrapper ${pkgs.quickshell}/bin/qs "$out/bin/ryotunes-qml" \
      --add-flags "-p $out/share/ryotunes/client" \
      --prefix QML_IMPORT_PATH : "${qmlImports}" \
      --prefix QML2_IMPORT_PATH : "${qmlImports}"
    # The client resolves skins relative to its own directory.
    test -d "$out/share/ryotunes/skins"
  '';

  meta = {
    description = "Ryoku's music app: daemon, CLI and native Quickshell client";
    homepage = "https://github.com/Ryoku-dev/ryotunes";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ryotunes";
  };
}
