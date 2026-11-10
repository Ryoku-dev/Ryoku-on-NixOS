# Ryotunes 2.0, the Lithic rewrite in Go and Gio that Ryoku Hyperion is built
# around (Ryoku-dev/ryotunes, branch hyperion). Layout and build follow its
# own release/arch/PKGBUILD: ryotunes (client), ryotunesd (daemon,
# socket-activated user unit), ryotunes-cli, ryotunes-sync, the desktop entry,
# icons and matugen template.
#
# NixOS differences, all about ownership:
# - The client starts its own daemon and the daemon reopens its own client
#   by store path, never through PATH, so an older Ryotunes elsewhere on PATH
#   (RyoMarket profiles, ~/.local/bin) cannot take over a session.
# - The tools the package depends on are on the wrapped PATH.
# - The in-app pacman updater is inert (no /usr/bin/pacman); NixOS updates it.
{ pkgs, src, version }:

let
  inherit (pkgs) lib;

  # Arch depends/optdepends that are run as programs.
  runtimePath = lib.makeBinPath [
    pkgs.yt-dlp
    pkgs.ffmpeg
    pkgs.xdg-utils
    pkgs.xdg-user-dirs
    pkgs.libsecret
    pkgs.cava
    pkgs.pipewire
  ];

  # Gio and mpv load these at run time.
  runtimeLibs = lib.makeLibraryPath [
    pkgs.vulkan-loader
    pkgs.libGL
    pkgs.wayland
    pkgs.libxkbcommon
    pkgs.libx11
    pkgs.libxcursor
    pkgs.libxfixes
    pkgs.mpv
  ];
in
pkgs.buildGoModule {
  pname = "ryotunes";
  inherit version src;

  vendorHash = "sha256-D4H8m37AXRMvEPLlPOssDc0RKW5bWB6bO7A/SjNJZQM=";

  subPackages = [
    "cmd/ryotunes"
    "cmd/ryotunesd"
    "cmd/ryotunes-cli"
    "cmd/ryotunes-sync"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/ryoku-dev/ryotunes/internal/version.Version=${version}"
  ];

  postPatch = ''
    substituteInPlace internal/client/conn/conn.go \
      --replace-fail 'exec.Command("ryotunesd")' "exec.Command(\"$out/bin/ryotunesd\")"
    substituteInPlace internal/daemon/server.go \
      --replace-fail 'exec.Command("ryotunes")' "exec.Command(\"$out/bin/ryotunes\")"
  '';

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.makeWrapper
  ];

  buildInputs = [
    pkgs.mpv
    pkgs.alsa-lib
    pkgs.flac
    pkgs.mpg123
    pkgs.libvorbis
    pkgs.libogg
    pkgs.wayland
    pkgs.libxkbcommon
    pkgs.libx11
    pkgs.libxcursor
    pkgs.libxfixes
    pkgs.libxcb
    pkgs.libGL.dev
    pkgs.vulkan-headers
    pkgs.vulkan-loader
    pkgs.libGL
  ];

  # Upstream runs `go test ./...` at release time; several tests need a
  # Wayland session.
  doCheck = false;

  postInstall = ''
    install -Dm755 release/diagnostics.sh "$out/bin/ryotunes-diagnostics"

    install -Dm644 release/linux/ryotunesd.socket "$out/lib/systemd/user/ryotunesd.socket"
    install -Dm644 release/linux/ryotunesd.service "$out/lib/systemd/user/ryotunesd.service"
    substituteInPlace "$out/lib/systemd/user/ryotunesd.service" \
      --replace-fail "ExecStart=/usr/bin/ryotunesd" "ExecStart=$out/bin/ryotunesd"

    install -Dm644 release/linux/ryotunes.desktop "$out/share/applications/ryotunes.desktop"
    substituteInPlace "$out/share/applications/ryotunes.desktop" \
      --replace-fail "Exec=ryotunes" "Exec=$out/bin/ryotunes"
    install -Dm644 release/linux/dev.ryoku.ryotunes.metainfo.xml \
      "$out/share/metainfo/dev.ryoku.ryotunes.metainfo.xml"
    install -Dm644 release/matugen/ryotunes.json "$out/share/ryotunes/matugen/ryotunes.json"

    for size in 32x32 64x64 128x128 256x256 512x512; do
      install -Dm644 "assets/icons/$size.png" "$out/share/icons/hicolor/$size/apps/ryotunes.png"
    done
    install -Dm644 assets/icons/ryotunes.svg "$out/share/icons/hicolor/scalable/apps/ryotunes.svg"

    install -Dm644 LICENSE "$out/share/licenses/ryotunes/LICENSE"
  '';

  postFixup = ''
    for bin in ryotunes ryotunesd ryotunes-cli ryotunes-sync; do
      wrapProgram "$out/bin/$bin" \
        --prefix PATH : ${runtimePath} \
        --prefix LD_LIBRARY_PATH : ${runtimeLibs}
    done
  '';

  meta = {
    description = "Ryoku's native Lithic music player";
    homepage = "https://github.com/Ryoku-dev/ryotunes/tree/hyperion";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ryotunes";
  };
}
