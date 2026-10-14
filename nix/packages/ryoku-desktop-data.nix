{ pkgs, src }:

pkgs.stdenv.mkDerivation {
  pname = "ryoku-desktop-data";
  version = "unstable";

  inherit src;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
  ];

  buildInputs = [
    pkgs.gtk3
    pkgs.webkitgtk_4_1
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    cfg="$out/share/ryoku/config"

    mkdir -p \
      "$cfg" \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/scalable/apps" \
      "$out/share/ryoku"

    # ── Hyprland ───────────────────────────────────────────────

    mkdir -p "$cfg/hypr"
    cp -a ryoku/hyprland/. "$cfg/hypr/"

    # Qt QML modules are exposed through the system profile on NixOS.
    substituteInPlace "$cfg/hypr/modules/env.lua" \
      --replace-fail \
        'os.getenv("HOME") .. "/.local/lib/qt6/qml"' \
        'os.getenv("HOME") .. "/.local/lib/qt6/qml:/run/current-system/sw/lib/qt-6/qml"'

    # ── Niri ──────────────────────────────────────────────────

    mkdir -p "$cfg/niri"
    cp -a ryoku/niri/. "$cfg/niri/"

    # ── Mango ─────────────────────────────────────────────────

    mkdir -p "$cfg/mango"
    cp -a ryoku/mango/. "$cfg/mango/"

    # NixOS owns graphical-session lifecycle through its declarative user
    # units. Route every compositor's upstream session handoff through the
    # Nix-native bootstrap instead of package-manager cutover machinery.
    substituteInPlace "$cfg/hypr/modules/autostart.lua" \
      --replace-fail \
        'ryoku-host session start xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service' \
        'ryoku-nix-session-start'

    substituteInPlace "$cfg/niri/autostart.kdl" \
      --replace-fail \
        'ryoku-host session start xdg-desktop-portal-gnome.service xdg-desktop-portal-gtk.service' \
        'ryoku-nix-session-start'

    substituteInPlace "$cfg/mango/autostart.conf" \
      --replace-fail \
        'ryoku-power-cutover session-start-logged' \
        'ryoku-nix-session-start'


    # ── Shared translation catalog ─────────────────────────────
    #
    # Upstream installs this at /usr/share/ryoku/i18n. Nix keeps the
    # same layout inside the immutable desktop-data output and exposes
    # it through RYOKU_I18N_DIR.
    mkdir -p "$out/share/ryoku/i18n"

    install -m0644       ryoku/i18n/langs.json       "$out/share/ryoku/i18n/langs.json"

    install -m0644       ryoku/i18n/catalog/*.json       "$out/share/ryoku/i18n/"

    # ── Main Quickshell shell ──────────────────────────────────

    mkdir -p "$cfg/quickshell"
    cp -a ryoku/shell/quickshell/. "$cfg/quickshell/"

    # Nomarchy is a shell-owned compatibility payload. Arch exposes it under
    # /usr/share/ryoku; Nix keeps the same data layout inside desktop-data.
    mkdir -p "$out/share/ryoku/nomarchy"
    cp -a ryoku/shell/nomarchy/. "$out/share/ryoku/nomarchy/"
    patchShebangs "$out/share/ryoku/nomarchy"

    # ── Ryoku Settings / Hub ───────────────────────────────────

    mkdir -p "$cfg/quickshell/hub"
    cp -a ryoku/hub/quickshell/. "$cfg/quickshell/hub/"

    # NixOS identity is a packaging invariant, not an upstream default. Upstream
    # Hub releases may reintroduce the Arch label during syncs; rewrite it here
    # as a final packaging step and fail the build if the Nix label disappears.
    # This keeps every Ryoku-on-NixOS generation pinned to the correct identity.
    hub_qml="$cfg/quickshell/hub/Hub.qml"
    sed -Ei 's/RYOKU[[:space:]]+(ARCH|NIXOS)/RYOKU NIX/Ig' "$hub_qml"

    if ! grep -Fq 'I18n.tr("RYOKU NIX")' "$hub_qml"; then
      echo "Ryoku Nix branding guard: Hub header is not pinned to RYOKU NIX" >&2
      exit 1
    fi

    if grep -Eiq 'RYOKU[[:space:]]+(ARCH|NIXOS)' "$hub_qml"; then
      echo "Ryoku Nix branding guard: non-Nix Hub branding survived packaging" >&2
      exit 1
    fi

    # ── First-party Ryoku apps ─────────────────────────────────
    #
    # Keep the same app contract as upstream: Quickshell apps ship their
    # config tree, while native apps with a CMakeLists.txt build into $out/bin.
    # Desktop entries, icons and helper scripts are shared by both shapes.

    for appdir in ryoku/apps/*/; do
      appname="$(basename "$appdir")"
      has_ui=0

      if [ -d "$appdir/quickshell" ]; then
        has_ui=1
        mkdir -p "$cfg/quickshell/$appname"
        cp -a "$appdir/quickshell/." "$cfg/quickshell/$appname/"
      fi

      if [ -f "$appdir/CMakeLists.txt" ]; then
        has_ui=1
        appbuild="$TMPDIR/ryoku-app-$appname"
        cmake \
          -S "$appdir" \
          -B "$appbuild" \
          -G Ninja \
          -DCMAKE_BUILD_TYPE=Release
        cmake --build "$appbuild"
        install -Dm755 \
          "$appbuild/$appname" \
          "$out/bin/$appname"
      fi

      if [ -d "$appdir/bin" ]; then
        for helper in "$appdir/bin/"*; do
          [ -f "$helper" ] || continue

          install -Dm755 \
            "$helper" \
            "$out/bin/$(basename "$helper")"
        done
      fi

      for desktop in "$appdir"*.desktop; do
        [ -f "$desktop" ] || continue

        install -Dm644 \
          "$desktop" \
          "$out/share/applications/$(basename "$desktop")"
      done

      if [ "$has_ui" -eq 1 ]; then
        icon="$appdir/quickshell/logo.svg"
        [ -f "$icon" ] || icon="$appdir/logo.svg"
        [ -f "$icon" ] || icon="ryoku/assets/brand/logo-mark.svg"

        install -Dm644 \
          "$icon" \
          "$out/share/icons/hicolor/scalable/apps/$appname.svg"
      fi
    done

    # ── Matugen / palette pipeline ─────────────────────────────

    mkdir -p "$cfg/matugen"
    cp -a ryoku/shell/matugen/. "$cfg/matugen/"

    # ── Qt / GTK appearance ────────────────────────────────────

    mkdir -p "$cfg/qt6ct"
    cp ryoku/shell/qt6ct/qt6ct.conf "$cfg/qt6ct/qt6ct.conf"

    mkdir -p "$cfg/gtk-3.0"
    cp ryoku/shell/gtk-3.0/settings.ini "$cfg/gtk-3.0/settings.ini"

    mkdir -p "$cfg/gtk-4.0"
    cp ryoku/shell/gtk-4.0/settings.ini "$cfg/gtk-4.0/settings.ini"

    # ── Application configs ────────────────────────────────────

    mkdir -p "$cfg/btop"
    cp ryoku/apps/btop/btop.conf "$cfg/btop/btop.conf"

    cp ryoku/apps/starship/starship.toml "$cfg/starship.toml"

    mkdir -p "$cfg/fastfetch"
    cp ryoku/apps/fastfetch/config.jsonc \
      "$cfg/fastfetch/config.jsonc"

    cp ryoku/assets/brand/ryoku-nixos.png \
      "$cfg/fastfetch/ryoku-nixos.png"

    mkdir -p "$cfg/kitty"
    cp -a ryoku/apps/kitty/. "$cfg/kitty/"

    # Ryoku's Fish configuration is part of the actual desktop package.
    mkdir -p "$cfg/fish/conf.d"
    cp ryoku/apps/fish/config.fish "$cfg/fish/config.fish"
    cp ryoku/apps/fish/conf.d/rashin.fish "$cfg/fish/conf.d/rashin.fish"

    mkdir -p "$cfg/wireplumber"
    cp -a ryoku/apps/wireplumber/. "$cfg/wireplumber/"

    mkdir -p "$cfg/yazi"
    cp ryoku/apps/yazi/yazi.toml "$cfg/yazi/yazi.toml"

    mkdir -p "$cfg/nvim"
    cp ryoku/apps/nvim/init.lua "$cfg/nvim/init.lua"
    cp ryoku/apps/nvim/.ryoku-lazyvim "$cfg/nvim/.ryoku-lazyvim"
    cp -a ryoku/apps/nvim/lua "$cfg/nvim/"

    mkdir -p "$cfg/pip"
    cp ryoku/apps/pip/pip.conf "$cfg/pip/pip.conf"

    cp ryoku/apps/chromium-flags.conf \
      "$cfg/chromium-flags.conf"

    ${pkgs.lib.optionalString (builtins.hasAttr "hyprland-preview-share-picker" pkgs) ''
      mkdir -p "$cfg/hyprland-preview-share-picker"
      cp ryoku/apps/hyprland-preview-share-picker/config.yaml \
        "$cfg/hyprland-preview-share-picker/config.yaml"
    ''}

    ${pkgs.lib.optionalString (! builtins.hasAttr "hyprland-preview-share-picker" pkgs) ''
      # NixOS stable releases may not package the preview picker. In that case
      # remove the custom command so xdg-desktop-portal-hyprland falls back to
      # its bundled hyprland-share-picker instead of returning no selection.
      sed -Ei '/^[[:space:]]*custom_picker_binary[[:space:]]*=[[:space:]]*hyprland-preview-share-picker[[:space:]]*$/d' \
        "$cfg/hypr/xdph.conf"
    ''}

    # ── User systemd session units ─────────────────────────────
    #
    # NixOS owns Ryoku's user services and targets declaratively
    # through nix/modules/ryoku.nix. Do not materialize upstream
    # units into ~/.config/systemd/user: user-local units override
    # the NixOS-managed definitions and upstream ExecStart paths
    # target /usr/bin.
    #
    # Upstream unit behaviour is mirrored by the NixOS module.

    # ── Helper binaries used by binds / shell ──────────────────

    for helper in ryoku/hyprland/scripts/ryoku-*; do
      [ -f "$helper" ] || continue

      install -Dm755 \
        "$helper" \
        "$out/bin/$(basename "$helper")"
    done

    # Keep Awake is compositor-neutral upstream now, so it lives under
    # ryoku/shell/scripts rather than the Hyprland helper directory.
    install -Dm755 \
      ryoku/shell/scripts/ryoku-cmd-caffeine \
      "$out/bin/ryoku-cmd-caffeine"

    # NixOS coreutils is a multicall binary and dispatches by argv[0].
    # Upstream uses `exec -a ryoku-caffeine-inhibit sleep infinity` to give
    # the inhibitor child a friendly process name, but renaming argv[0] makes
    # Nix coreutils reject it as an unknown applet. The surrounding
    # systemd-inhibit process/unit already identifies and owns the inhibitor.
    substituteInPlace "$out/bin/ryoku-cmd-caffeine" \
      --replace-fail \
        "exec -a ryoku-caffeine-inhibit sleep infinity" \
        "exec sleep infinity"

    install -Dm755 \
      ryoku/shell/quickshell/plugins/ryoku-plugins-place \
      "$out/bin/ryoku-plugins-place"

    install -Dm755 \
      ryoku/apps/fastfetch/ryoku-fastfetch \
      "$out/bin/ryoku-fastfetch"

    for helper in \
      ryoku/rashin/usage/claude-usage \
      ryoku/rashin/usage/codex-usage \
      ryoku/rashin/usage/opencode-usage
    do
      install -Dm755 \
        "$helper" \
        "$out/bin/$(basename "$helper")"
    done

    # ── Ryotunes ───────────────────────────────────────────────
    #
    # Current Ryoku ships Ryotunes as a compiled application.
    # Musubi packages it independently instead of materializing
    # the retired browser-wrapper files from ryoku/apps.

    # ── Lockscreen ─────────────────────────────────────────────

    mkdir -p "$out/share/ryoku/lockscreen"

    cp -a \
      ryoku/lockscreen/qylock \
      "$out/share/ryoku/lockscreen/qylock"

    install -Dm755 \
      ryoku/lockscreen/install-qylock \
      "$out/share/ryoku/lockscreen/install-qylock"

    patchShebangs "$out/share/ryoku/lockscreen/install-qylock"

    # RYOKU NIXOS QYLOCK WRITABLE COPY
    #
    # install-qylock stages with `cp -a`. When its bundle comes from /nix/store,
    # that faithfully preserves the store's read-only directory modes. The
    # installer then creates themes_link inside the copied lockscreen and dies
    # with EACCES. Make only the user-owned copies writable after each copy.
    substituteInPlace "$out/share/ryoku/lockscreen/install-qylock" \
      --replace-fail \
        'user cp -a "$BUNDLE/quickshell-lockscreen" "$LOCK_DIR"' \
        'user cp -a "$BUNDLE/quickshell-lockscreen" "$LOCK_DIR"
user chmod -R u+w "$LOCK_DIR"' \
      --replace-fail \
        'user cp -a "$BUNDLE/themes/clockwork/orbital" "$STAGED_THEME_DIR/clockwork/orbital"' \
        'user cp -a "$BUNDLE/themes/clockwork/orbital" "$STAGED_THEME_DIR/clockwork/orbital"
user chmod -R u+w "$STAGED_THEME_DIR"' \
      --replace-fail \
        'user cp -a "$BUNDLE/themes/clockwork/orbital" "$QYLOCK_DIR/themes/clockwork/orbital"' \
        'user cp -a "$BUNDLE/themes/clockwork/orbital" "$QYLOCK_DIR/themes/clockwork/orbital"
user chmod -R u+w "$QYLOCK_DIR/themes/clockwork/orbital"'

    # ── Desktop integration ────────────────────────────────────

    install -Dm644 \
      ryoku/apps/nautilus/ryoku-stash-menu.py \
      "$out/share/ryoku/nautilus/ryoku-stash-menu.py"

    # ── Browser integration ────────────────────────────────────

    mkdir -p "$out/share/ryoku/browser"

    (
      cd ryoku/browser
      sh ./build.sh
    )

    cp -a ryoku/browser/. "$out/share/ryoku/browser/"

    # ── Wallpapers ─────────────────────────────────────────────

    mkdir -p "$out/share/ryoku/wallpapers"

    if [ -d ryoku/assets/wallpapers ]; then
      cp -a \
        ryoku/assets/wallpapers/. \
        "$out/share/ryoku/wallpapers/"
    fi

    # ── Ryoku decor artwork ────────────────────────────────────

    mkdir -p "$out/share/ryoku/ryodecors"

    cp -a \
      ryoku/assets/ryodecors/. \
      "$out/share/ryoku/ryodecors/"

    # ── Brand assets ───────────────────────────────────────────

    mkdir -p "$out/share/ryoku/brand"

    cp -a \
      ryoku/assets/brand/. \
      "$out/share/ryoku/brand/"

    chmod -R u=rwX,go=rX "$out/share"

    runHook postInstall
  '';
  meta = {
    description = "Ryoku desktop configuration, assets, applications and integration data";
    homepage = "https://github.com/Ryoku-dev/ryoku-arch";
    license = pkgs.lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
  };

}
