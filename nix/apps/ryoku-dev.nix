{ pkgs, src, ryoku }:

let
  qtQmlPath = pkgs.lib.makeSearchPath "lib/qt-6/qml" [
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qtmultimedia
    pkgs.qt6.qt5compat
    pkgs.qt6.qtsvg
    pkgs.qt6.qtimageformats
  ];
in

pkgs.writeShellApplication {
  name = "ryoku-dev";

  runtimeInputs = with pkgs; [
    # ───────────────────────────────────────────────────────────
    # Ryoku / compositor
    # ───────────────────────────────────────────────────────────
    quickshell
    hyprland

    # ───────────────────────────────────────────────────────────
    # Qt runtime
    # ───────────────────────────────────────────────────────────
    qt6.qtdeclarative
    qt6.qtmultimedia
    qt6.qt5compat
    qt6.qtsvg
    qt6.qtimageformats

    # ───────────────────────────────────────────────────────────
    # Wallpaper / theming
    # ───────────────────────────────────────────────────────────
    matugen
    imagemagick
    hyprpicker

    # ───────────────────────────────────────────────────────────
    # Clipboard / Wayland
    # ───────────────────────────────────────────────────────────
    wl-clipboard
    grim
    slurp
    wtype

    # ───────────────────────────────────────────────────────────
    # Audio / media
    # ───────────────────────────────────────────────────────────
    wireplumber
    pulseaudio
    cava
    playerctl
    mpv

    # ───────────────────────────────────────────────────────────
    # Power / hardware
    # ───────────────────────────────────────────────────────────
    brightnessctl
    upower
    hypridle

    # ───────────────────────────────────────────────────────────
    # Helpers
    # ───────────────────────────────────────────────────────────
    jq
    glib
    curl
    python3
    openssl
    libnotify
    xdg-utils

    # ───────────────────────────────────────────────────────────
    # Capture
    # ───────────────────────────────────────────────────────────
    tesseract
    zbar
    wf-recorder
    hyprsunset

    # ───────────────────────────────────────────────────────────
    # Apps expected by Ryoku
    # ───────────────────────────────────────────────────────────
    kitty
    nautilus
    gtk3

    git
  ];

  text = ''
    if [ -z "''${WAYLAND_DISPLAY:-}" ]; then
      printf '%s\n' \
        "ryoku-dev must be started inside a running Wayland session."
      exit 1
    fi

    if [ -n "''${RYOKU_CHECKOUT:-}" ]; then
      root="$RYOKU_CHECKOUT"
    elif git_root="$(git rev-parse --show-toplevel 2>/dev/null)" &&
         [ -d "$git_root/ryoku/shell" ]; then
      root="$git_root"
    else
      root="${src}"
    fi

    shell_dir="$root/ryoku/shell"
    ryoku_qml="${ryoku.qml}/lib/qt-6/qml"

    if [ ! -d "$shell_dir/quickshell/shell" ]; then
      printf 'Ryoku shell config not found at:\n  %s\n' \
        "$shell_dir/quickshell/shell"
      exit 1
    fi

    if [ ! -d "$ryoku_qml/Ryoku/PluginKit" ]; then
      printf '%s\n' "Ryoku.PluginKit is missing."
      exit 1
    fi

    if [ ! -d "$ryoku_qml/Ryoku/Blobs" ]; then
      printf '%s\n' "Ryoku.Blobs is missing."
      exit 1
    fi

    export RYOKU_SHELL_DIR="$shell_dir"

    qml_path="$shell_dir/quickshell:$ryoku_qml:${qtQmlPath}"

    export QML_IMPORT_PATH="$qml_path''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
    export QML2_IMPORT_PATH="$qml_path''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

    printf '\n'
    printf 'Ryoku Nix development session\n'
    printf '────────────────────────────────────────\n'
    printf 'Checkout     %s\n' "$root"
    printf 'Shell        %s\n' "$shell_dir"
    printf 'Ryoku QML    %s\n' "$ryoku_qml"
    printf 'Qt QML       %s\n' "${qtQmlPath}"
    printf '\n'
    printf 'Ctrl+C       stop Ryoku\n'
    printf '────────────────────────────────────────\n\n'

    exec ${ryoku.shell}/bin/ryoku-shell daemon
  '';
}
