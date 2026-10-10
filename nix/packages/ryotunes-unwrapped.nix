{
  pkgs,
  ryotunesSrc,
}:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "ryotunes-unwrapped";
  version = "1.1.6";

  src = ryotunesSrc;

  patches = [
    ../patches/ryotunes-spotify-mpris.patch
    ../patches/ryotunes-youtube-browser-auth.patch
    ../patches/ryotunes-youtube-session-cookie-rotation.patch
    ../patches/ryotunes-youtube-auth-resilience.patch
    ../patches/ryotunes-youtube-auth-persistence.patch
    ../patches/ryotunes-youtube-cookie-durability.patch
  ];

  # Cargo dependencies include pinned librespot Git revisions.
  # Keep the vendor hash tied to the exact upstream release.
  cargoHash = "sha256-SoWIji85omW32TyXwk/zBzreShj/ZVXkOabHsHbxa1I=";

  # The Linux application launches its native QML client.
  # The Tauri build currently also requires the Svelte/Vite payload.
  pnpmDeps = pkgs.fetchPnpmDeps {
    pname = "ryotunes-ui";
    inherit version;

    src = ryotunesSrc + "/ui";

    fetcherVersion = 4;

    hash = "sha256-L0HRYhFO5A0qqwdiYzN+h28kV7vAqB3up+Zu4ShYnBo=";
  };

  pnpmRoot = "ui";

  nativeBuildInputs = [
    pkgs.pkg-config

    pkgs.nodejs
    pkgs.pnpm
    pkgs.pnpmConfigHook

    pkgs.wrapGAppsHook3

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

  preBuild = ''
    export HOME="$TMPDIR"

    (
      cd ui
      pnpm build
    )

    test -f ui/build/index.html
  '';

  cargoBuildFlags = [
    "--package"
    "ryotunes"

    "--package"
    "sync-server"

    "--package"
    "ryotunesd"

    "--package"
    "ryotunes-cli"
  ];

  # Upstream runs its full workspace test suite at release time.
  # The Ryoku Nix derivation keeps packaging deterministic here;
  # runtime and integration tests happen against the assembled
  # NixOS generation.
  doCheck = false;

  installPhase = ''
    runHook preInstall

    install_bin() {
      local name="$1"
      local binary

      binary="$(
        find target \
          -type f \
          -path "*/release/$name" \
          -perm -0100 \
          -print \
          -quit
      )"

      if [ -z "$binary" ]; then
        printf 'ryoku-ryotunes: built binary missing: %s\n' \
          "$name" >&2
        exit 1
      fi

      install -Dm755 \
        "$binary" \
        "$out/bin/$name"
    }

    mkdir -p \
      "$out/bin" \
      "$out/share/ryotunes/client" \
      "$out/share/ryotunes/skins" \
      "$out/share/ryotunes/matugen" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/32x32/apps" \
      "$out/share/icons/hicolor/64x64/apps" \
      "$out/share/icons/hicolor/128x128/apps" \
      "$out/share/icons/hicolor/256x256/apps" \
      "$out/share/icons/hicolor/512x512/apps" \
      "$out/share/metainfo" \
      "$out/share/licenses/ryotunes" \
      "$out/share/doc/ryotunes"

    install_bin ryotunes
    install_bin ryotunes-sync
    install_bin ryotunesd
    install_bin ryotunes-cli

    # Native Quickshell client.
    cp -r \
      client/. \
      "$out/share/ryotunes/client/"

    rm -rf \
      "$out/share/ryotunes/client/tests"

    find "$out/share/ryotunes/client" \
      -type d \
      -exec chmod 755 {} +

    find "$out/share/ryotunes/client" \
      -type f \
      -exec chmod 644 {} +

    # Shipped appearance system.
    cp -r \
      skins/. \
      "$out/share/ryotunes/skins/"

    find "$out/share/ryotunes/skins" \
      -type d \
      -exec chmod 755 {} +

    find "$out/share/ryotunes/skins" \
      -type f \
      -exec chmod 644 {} +

    install -Dm644 \
      matugen/ryotunes.json \
      "$out/share/ryotunes/matugen/ryotunes.json"

    install -Dm644 \
      packaging/linux/ryotunes.desktop \
      "$out/share/applications/ryotunes.desktop"

    install -Dm644 \
      packaging/linux/dev.ryoku.ryotunes.metainfo.xml \
      "$out/share/metainfo/dev.ryoku.ryotunes.metainfo.xml"

    install -Dm644 \
      src-tauri/icons/32x32.png \
      "$out/share/icons/hicolor/32x32/apps/ryotunes.png"

    install -Dm644 \
      src-tauri/icons/64x64.png \
      "$out/share/icons/hicolor/64x64/apps/ryotunes.png"

    install -Dm644 \
      src-tauri/icons/128x128.png \
      "$out/share/icons/hicolor/128x128/apps/ryotunes.png"

    install -Dm644 \
      src-tauri/icons/128x128@2x.png \
      "$out/share/icons/hicolor/256x256/apps/ryotunes.png"

    install -Dm644 \
      src-tauri/icons/icon.png \
      "$out/share/icons/hicolor/512x512/apps/ryotunes.png"

    install -Dm755 \
      scripts/diagnostics.sh \
      "$out/bin/ryotunes-diagnostics"

    install -Dm644 \
      LICENSE \
      "$out/share/licenses/ryotunes/LICENSE"

    install -Dm644 \
      README.md \
      "$out/share/doc/ryotunes/README.md"

    install -Dm644 \
      UPSTREAM.md \
      "$out/share/doc/ryotunes/UPSTREAM.md"

    runHook postInstall
  '';

  meta = {
    description =
      "Native Ryoku music client with daemon, CLI and QML frontend";

    homepage =
      "https://github.com/Ryoku-dev/ryotunes";

    license = pkgs.lib.licenses.gpl3Plus;

    platforms = [
      "x86_64-linux"
    ];

    mainProgram = "ryotunes";
  };
}
