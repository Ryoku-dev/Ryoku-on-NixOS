{ self, ryokuNixpkgs, hermesAgent }:

{ config, lib, pkgs, options, ... }:

let
  cfg = config.programs.ryoku;

  system = pkgs.stdenv.hostPlatform.system;

  ryokuPkgs = self.packages.${system};

  ryokuShell = ryokuPkgs.ryoku-shell;
  ryokuRashin = ryokuPkgs.ryoku-rashin;
  ryokuBundle = ryokuPkgs.ryoku-bundle;
  ryokuHelpers = ryokuPkgs.ryoku-helpers;
  ryokuSystemBridge = ryokuPkgs.ryoku-nixos-system-bridge;
  ryokuDesktopData = ryokuPkgs.ryoku-desktop-data;
  ryokuRyogami = ryokuPkgs.ryoku-ryogami;
  ryokuSkwdPaper = ryokuPkgs.ryoku-skwd-paper;
  ryokuPaletteBridge = ryokuPkgs.ryoku-palette-bridge;
  ryokuQuickshell = ryokuNixpkgs.quickshell;

  # Keep the preview share picker in Ryoku's pinned package universe rather
  # than the host package set. NixOS stable releases may not expose this
  # attribute even though Ryoku's xdph.conf expects the binary.
  ryokuPreviewSharePicker =
    lib.attrByPath [ "hyprland-preview-share-picker" ] null ryokuNixpkgs;
  ryokuRyotunes = ryokuPkgs.ryoku-ryotunes;
  ryokuWmHyprland = ryokuPkgs.ryoku-wm-hyprland;
  ryokuWmNiri = ryokuPkgs.ryoku-wm-niri;
  ryokuWmMango = ryokuPkgs.ryoku-wm-mango;

  # Hyprland plugins are ABI-sensitive, so the compositor, portal and
  # plugin bundle must all come from Ryoku's own locked package set.
  ryokuHyprland = ryokuPkgs.ryoku-hyprland;
  ryokuHyprlandPortal = ryokuPkgs.ryoku-xdg-desktop-portal-hyprland;
  ryokuNiri = ryokuPkgs.ryoku-niri;
  ryokuMango = ryokuPkgs.ryoku-mango;
  ryokuXwaylandSatellite = ryokuPkgs.ryoku-xwayland-satellite;
  ryokuMatugen = ryokuPkgs.ryoku-matugen;
  ryokuHyprPlugins = ryokuPkgs.ryoku-hypr-plugins;
  ryokuCursorMaterial = ryokuPkgs.ryoku-cursor-material;
  ryokuMapleMonoNF = ryokuPkgs.ryoku-maple-mono-nf;
  materializer = ryokuPkgs.ryoku-materialize;

  # The shell, suspend guard and Hub lock preview all enter qylock through this
  # stable launcher. Keep it in the Nix closure instead of assuming the Arch
  # package installed /usr/bin/ryoku-qylock-lock.
  ryokuQylockLock = pkgs.runCommand "ryoku-qylock-lock" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p "$out/bin"
    cp ${../../ryoku/lockscreen/ryoku-qylock-lock} "$out/bin/ryoku-qylock-lock"
    chmod 0755 "$out/bin/ryoku-qylock-lock"
    patchShebangs "$out/bin/ryoku-qylock-lock"
    wrapProgram "$out/bin/ryoku-qylock-lock" \
      --prefix PATH : ${lib.makeBinPath [ pkgs.util-linux ]}
  '';

  ryokuNixSessionStart = pkgs.writeShellScriptBin "ryoku-nix-session-start" ''
    set -euo pipefail

    sid="''${XDG_SESSION_ID:-}"
    ready=0

    if [ -n "$sid" ]; then
      attempt=0

      while [ "$attempt" -lt 150 ]; do
        session_type="$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
        session_class="$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Class --value 2>/dev/null || true)"
        session_active="$(${pkgs.systemd}/bin/loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"

        if [ "$session_type" = "wayland" ] &&
           { [ "$session_class" = "user" ] || [ "$session_class" = "user-early" ]; } &&
           [ "$session_active" = "yes" ]
        then
          ready=1
          break
        fi

        attempt=$((attempt + 1))
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      if [ "$ready" -ne 1 ]; then
        printf 'ryoku-nix-session-start: login1 did not expose graphical session %s\n' "$sid" >&2
        exit 1
      fi
    fi

    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all

    # Older Ryoku releases enabled user units into ~/.config/systemd/user. A
    # dangling user-local .wants link outranks the declarative /etc link, so
    # clean that migration state before systemd resolves the session target.
    ${materializer}/bin/ryoku-materialize || true
    ${pkgs.systemd}/bin/systemctl --user daemon-reload

    ${pkgs.systemd}/bin/systemctl --user reset-failed       ryoku-shell.service       ryogami.service       hypridle.service       >/dev/null 2>&1 || true

    ${pkgs.systemd}/bin/systemctl --user restart ryoku-session.target

    ${pkgs.systemd}/bin/systemctl --user try-restart       xdg-desktop-portal.service       xdg-desktop-portal-gnome.service       xdg-desktop-portal-gtk.service       xdg-desktop-portal-wlr.service       >/dev/null 2>&1 || true
  '';

  # Niri's stock display-manager entry can start before Ryoku has ever
  # materialized ~/.config/niri. In that state Niri falls back to its bare
  # default config, which also means the Ryoku session bootstrap is absent and
  # ryoku-materialize.service can never be reached. Break that cycle at the
  # session boundary by seeding the config before handing off to niri-session.
  ryokuNiriSession = pkgs.runCommand "ryoku-niri-session" {
    passthru.providedSessions = [ "ryoku-niri" ];
  } ''
    mkdir -p "$out/bin" "$out/share/wayland-sessions"

    cat > "$out/bin/ryoku-niri-session" <<'EOF'
#!${pkgs.runtimeShell}
set -eu

# config.kdl and autostart.kdl are generation-owned entrypoints. Refresh them
# before Niri parses either file so a branch/generation switch cannot boot with
# stale compositor config and deadlock before ryoku-materialize.service starts.
${materializer}/bin/ryoku-materialize

export PATH="${lib.makeBinPath [
  ryokuNiri
  pkgs.bash
  pkgs.coreutils
  pkgs.dbus
  pkgs.gnugrep
  pkgs.procps
  pkgs.systemd
]}:$PATH"

exec ${ryokuNiri}/bin/niri-session "$@"
EOF

    chmod 0755 "$out/bin/ryoku-niri-session"

    cat > "$out/share/wayland-sessions/ryoku-niri.desktop" <<EOF
[Desktop Entry]
Name=Niri (Ryoku)
Comment=Ryoku desktop on the Niri compositor
Exec=$out/bin/ryoku-niri-session
Type=Application
DesktopNames=niri
EOF
  '';

  # Mango's stock session starts the compositor directly. Ryoku needs its
  # writable config tree before Mango reads config.conf, so the greeter entry
  # closes the first-login gap by materializing once when that entry is absent.
  ryokuMangoSession = pkgs.runCommand "ryoku-mango-session" {
    passthru.providedSessions = [ "ryoku-mango" ];
  } ''
    mkdir -p "$out/bin" "$out/share/wayland-sessions"

    cat > "$out/bin/ryoku-mango-session" <<'EOF'
#!${pkgs.runtimeShell}
set -eu

config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"

if [ ! -f "$config_home/mango/config.conf" ]; then
  ${materializer}/bin/ryoku-materialize || true
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=mango
export XDG_SESSION_DESKTOP=mango
export DESKTOP_SESSION=ryoku-mango

exec ${ryokuMango}/bin/mango "$@"
EOF

    chmod 0755 "$out/bin/ryoku-mango-session"

    cat > "$out/share/wayland-sessions/ryoku-mango.desktop" <<'EOF'
[Desktop Entry]
Name=Mango (Ryoku)
Comment=Ryoku desktop on the MangoWM compositor
Exec=ryoku-mango-session
Icon=mango
Type=Application
DesktopNames=mango;wlroots
EOF
  '';

  # ───────────────────────────────────────────────────────────
  # Ryoku qylock
  #
  # Upstream's installer writes directly into /usr/share and
  # ~/.local/share. On NixOS the SDDM half is immutable while
  # the in-session lock is materialized into the user's home.
  # ───────────────────────────────────────────────────────────

  qylockMaterializer = pkgs.writeShellScript "ryoku-qylock-materialize" ''
    set -euo pipefail

    source_root="${ryokuDesktopData}/share/ryoku/lockscreen/qylock"

    data_home="$HOME/.local/share"
    config_home="$HOME/.config"

    lock_dir="$data_home/quickshell-lockscreen"
    themes_dir="$data_home/qylock/themes"

    if [ ! -f "$source_root/quickshell-lockscreen/lock_shell.qml" ]; then
      echo "ryoku-qylock-materialize: lockscreen payload is missing" >&2
      exit 1
    fi

    if [ ! -f "$source_root/themes/clockwork/orbital/Main.qml" ]; then
      echo "ryoku-qylock-materialize: fallback theme is missing" >&2
      exit 1
    fi

    install -d \
      "$data_home" \
      "$themes_dir" \
      "$themes_dir/clockwork" \
      "$config_home/qylock"

    # Ryoku owns the lock runtime itself. Refresh it atomically enough for
    # normal generation switches while keeping user-installed themes separate.
    tmp="$(mktemp -d "$data_home/.quickshell-lockscreen.XXXXXX")"
    trap 'rm -rf "$tmp"' EXIT

    cp -a "$source_root/quickshell-lockscreen/." "$tmp/"
    chmod -R u+w "$tmp"
    chmod 700 "$tmp/lock.sh"

    # NixOS does not provide Ryoku's Arch-only fingerprint grosshack.
    # Keep the fingerprint conversation fail-closed and give typed passwords
    # their own PAM service, matching qylock's parallel auth design. Every
    # module path points into the active NixOS PAM package.
    pam_dir="$tmp/assets/pam"
    mkdir -p "$pam_dir"

    cat > "$pam_dir/ryoku-lock" <<'EOF'
#%PAM-1.0
#
# Fingerprint authentication is unavailable in the NixOS qylock runtime.
# Deny it explicitly while retaining valid account and session handling.

auth       required  ${config.security.pam.package}/lib/security/pam_deny.so
account    required  ${config.security.pam.package}/lib/security/pam_unix.so
password   required  ${config.security.pam.package}/lib/security/pam_deny.so
session    required  ${config.security.pam.package}/lib/security/pam_unix.so
EOF

    chmod 600 "$pam_dir/ryoku-lock"

    cat > "$pam_dir/ryoku-lock-pw" <<'EOF'
#%PAM-1.0
#
# Password authentication runs separately from the fingerprint conversation.

auth       required  ${config.security.pam.package}/lib/security/pam_unix.so nullok
account    required  ${config.security.pam.package}/lib/security/pam_unix.so
password   required  ${config.security.pam.package}/lib/security/pam_deny.so
session    required  ${config.security.pam.package}/lib/security/pam_unix.so
EOF

    chmod 600 "$pam_dir/ryoku-lock-pw"

    # Linux-PAM probes this fallback service for a custom config directory.
    # Unknown services must fail closed.
    cat > "$pam_dir/other" <<'EOF'
#%PAM-1.0
auth       required  ${config.security.pam.package}/lib/security/pam_deny.so
account    required  ${config.security.pam.package}/lib/security/pam_deny.so
password   required  ${config.security.pam.package}/lib/security/pam_deny.so
session    required  ${config.security.pam.package}/lib/security/pam_deny.so
EOF

    chmod 600 "$pam_dir/other"

    rm -rf "$lock_dir"
    mv "$tmp" "$lock_dir"
    trap - EXIT

    # Refresh only Ryoku's built-in fallback theme. RyoStore/user themes survive.
    rm -rf "$themes_dir/clockwork/orbital"
    cp -a \
      "$source_root/themes/clockwork/orbital" \
      "$themes_dir/clockwork/orbital"

    chmod -R u+w "$themes_dir/clockwork/orbital"

    rm -rf "$lock_dir/themes_link"
    ln -s "$themes_dir" "$lock_dir/themes_link"

    # Seed the default once. Never overwrite a user's selected skin.
    if [ ! -s "$config_home/qylock/theme" ]; then
      printf '%s\n' 'clockwork/orbital' > "$config_home/qylock/theme"
      chmod 600 "$config_home/qylock/theme"
    fi
  '';

  # Upstream's SDDM 0.21 recovery watches for the daemon running with no
  # greeter/session helper. NixOS owns the display-manager unit, so translate
  # the one privileged host action into a direct restart of that unit rather
  # than routing it through a mutable distro service backend.
  ryokuGreeterGuardHost = pkgs.writeShellScriptBin "ryoku-greeter-guard-host" ''
    set -eu
    if [ "$#" -eq 4 ] && [ "$1" = svc ] && [ "$2" = --system ] &&
       [ "$3" = restart ] && [ "$4" = sddm ]; then
      exec ${pkgs.systemd}/bin/systemctl restart display-manager.service
    fi
    printf 'ryoku-greeter-guard-host: unsupported request\n' >&2
    exit 2
  '';

  ryokuGreeterGuard = pkgs.writeShellApplication {
    name = "ryoku-greeter-guard";
    runtimeInputs = with pkgs; [ coreutils util-linux ];
    text = ''
      export RYOKU_GREETER_GUARD_HOST=${ryokuGreeterGuardHost}/bin/ryoku-greeter-guard-host
      exec ${pkgs.bash}/bin/bash ${../../ryoku/lockscreen/sddm/ryoku-greeter-guard} "$@"
    '';
  };

  # SDDM itself remains declaratively configured as the fixed "ryoku" theme.
  # Only the selected theme payload is mutable.
  ryokuSddmStateDir = "/var/lib/ryoku/sddm-theme";

  ryokuSddmThemeApply = pkgs.writeShellScriptBin "ryoku-sddm-theme-apply" ''
    set -euo pipefail

    slug="''${1:-}"

    case "$slug" in
      ""|/*|*".."*)
        printf 'ryoku-sddm-theme-apply: invalid skin slug: %s\n' "$slug" >&2
        exit 2
        ;;
    esac

    uid="''${PKEXEC_UID:-}"
    if [ -z "$uid" ]; then
      uid="''${SUDO_UID:-}"
    fi

    case "$uid" in
      ""|*[!0-9]*)
        printf 'ryoku-sddm-theme-apply: cannot determine invoking user\n' >&2
        exit 2
        ;;
    esac

    if [ "$uid" = "0" ]; then
      printf 'ryoku-sddm-theme-apply: refusing root as the theme owner\n' >&2
      exit 2
    fi

    passwd_line="$(${pkgs.getent}/bin/getent passwd "$uid" || true)"
    home="$(printf '%s\n' "$passwd_line" | ${pkgs.coreutils}/bin/cut -d: -f6)"

    if [ -z "$home" ]; then
      printf 'ryoku-sddm-theme-apply: cannot resolve home for uid %s\n' "$uid" >&2
      exit 2
    fi

    themes_root="$home/.local/share/qylock/themes"
    src="$themes_root/$slug"

    themes_real="$(${pkgs.coreutils}/bin/readlink -f -- "$themes_root" 2>/dev/null || true)"
    src_real="$(${pkgs.coreutils}/bin/readlink -f -- "$src" 2>/dev/null || true)"

    if [ -z "$themes_real" ] || [ -z "$src_real" ]; then
      printf 'ryoku-sddm-theme-apply: skin is not installed: %s\n' "$slug" >&2
      exit 1
    fi

    case "$src_real" in
      "$themes_real"/*)
        ;;
      *)
        printf 'ryoku-sddm-theme-apply: skin escaped the qylock theme root\n' >&2
        exit 2
        ;;
    esac

    if [ ! -f "$src_real/Main.qml" ]; then
      printf 'ryoku-sddm-theme-apply: skin has no Main.qml: %s\n' "$slug" >&2
      exit 1
    fi

    ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/ryoku

    tmp="$(${pkgs.coreutils}/bin/mktemp -d /var/lib/ryoku/.sddm-theme.XXXXXX)"
    trap '${pkgs.coreutils}/bin/rm -rf "$tmp"' EXIT

    ${pkgs.coreutils}/bin/cp \
      -a \
      --no-preserve=ownership \
      "$src_real/." \
      "$tmp/"

    ${pkgs.coreutils}/bin/chown -R root:root "$tmp"
    ${pkgs.coreutils}/bin/chmod -R a+rX "$tmp"

    ${pkgs.coreutils}/bin/rm -rf /var/lib/ryoku/sddm-theme
    ${pkgs.coreutils}/bin/mv "$tmp" /var/lib/ryoku/sddm-theme

    trap - EXIT

    printf 'Ryoku SDDM theme -> %s\n' "$slug"
  '';

  # The path SDDM sees is immutable, while its payload lives in /var/lib.
  # This keeps services.displayManager.sddm.theme permanently set to "ryoku"
  # and lets Hub change the visual theme without rewriting NixOS configuration.
  ryokuSddmTheme = pkgs.runCommand "ryoku-sddm-theme" { } ''
    mkdir -p "$out/share/sddm/themes"
    ln -s "${ryokuSddmStateDir}" "$out/share/sddm/themes/ryoku"
  '';


  ryokuUdevRules = pkgs.runCommand "ryoku-udev-rules" {
    nativeBuildInputs = [
      pkgs.makeWrapper
    ];
  } ''
    rules="$out/lib/udev/rules.d"
    libexec="$out/libexec"

    mkdir -p "$rules" "$libexec"

    install -Dm755 \
      ${self}/system/hardware/input/ryoku-hw-qmk \
      "$libexec/ryoku-hw-qmk"

    patchShebangs "$libexec/ryoku-hw-qmk"

    wrapProgram "$libexec/ryoku-hw-qmk" \
      --prefix PATH : ${pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
      ]}

    install -Dm644 \
      ${self}/system/hardware/ddc/60-ryoku-i2c.rules \
      "$rules/60-ryoku-i2c.rules"

    # Ryoku does not build PCR-signed UKIs. Tell systemd that NvPCR setup is
    # unavailable instead of failing the TPM setup/login measurement units on
    # every boot. The upstream rule is command-free, so it is portable as-is.
    install -Dm644 \
      ${self}/system/hardware/tpm/60-ryoku-tpm-nvpcr.rules \
      "$rules/60-ryoku-tpm-nvpcr.rules"

    install -Dm644 \
      ${self}/system/hardware/input/62-ryoku-qmk-hid.rules \
      "$rules/62-ryoku-qmk-hid.rules"

    install -Dm644 \
      ${self}/system/hardware/audio/70-ryoku-maono.rules \
      "$rules/70-ryoku-maono.rules"

    install -Dm644 \
      ${self}/system/hardware/input/72-ryoku-keyboard-uaccess.rules \
      "$rules/72-ryoku-keyboard-uaccess.rules"

    install -Dm644 \
      ${self}/system/hardware/display/90-ryoku-backlight.rules \
      "$rules/90-ryoku-backlight.rules"

    install -Dm644 \
      ${self}/system/hardware/gpu/90-ryoku-gpu.rules \
      "$rules/90-ryoku-gpu.rules"

    substituteInPlace "$rules/62-ryoku-qmk-hid.rules" \
      --replace-fail \
        "/usr/bin/ryoku-hw-qmk" \
        "$libexec/ryoku-hw-qmk"

    substituteInPlace "$rules/90-ryoku-backlight.rules" \
      --replace-fail \
        "/usr/bin/chgrp" \
        "${pkgs.coreutils}/bin/chgrp" \
      --replace-fail \
        "/usr/bin/chmod" \
        "${pkgs.coreutils}/bin/chmod"

    substituteInPlace "$rules/90-ryoku-gpu.rules" \
      --replace-fail \
        "/bin/sh" \
        "${pkgs.runtimeShell}" \
      --replace-fail \
        "| sed " \
        "| ${pkgs.gnused}/bin/sed " \
      --replace-fail \
        "| tr " \
        "| ${pkgs.coreutils}/bin/tr "
  '';

  qmlRoot = "${ryokuPkgs.ryoku-qml}/lib/qt-6/qml";

  # Ryoku treats these as hard desktop dependencies. Keep them
  # explicit rather than optional so upstream parity cannot
  # silently degrade when a package disappears from nixpkgs.
  # Space Grotesk is part of Google Fonts. Using nixpkgs'
  # generated Google Fonts package avoids carrying another font
  # derivation solely for Ryoku.
  spaceGrotesk = pkgs.google-fonts.override {
    fonts = [ "Space Grotesk" ];
  };

  # waifu2x-ncnn-vulkan is not currently exposed by our pinned
  # nixpkgs. Ryoku therefore carries a pinned upstream runtime
  # package alongside its other first-party dependencies.
  ryokuWaifu2x = ryokuPkgs.ryoku-waifu2x;

  waifu2xModels =
    "${ryokuWaifu2x}/share/waifu2x-ncnn-vulkan/models-cunet";

  # Upstream ships mpv together with mpv-mpris so radio/media
  # playback appears on the desktop's MPRIS bus.
  mpvWithMpris = pkgs.mpv.override {
    scripts = [
      pkgs.mpvScripts.mpris
    ];
  };

  qtQmlPath = lib.makeSearchPath "lib/qt-6/qml" [
    ryokuNixpkgs.qt6.qtdeclarative
    ryokuNixpkgs.qt6.qtmultimedia
    ryokuNixpkgs.qt6.qtwayland
    ryokuNixpkgs.qt6.qt5compat
    ryokuNixpkgs.qt6.qtsvg
    ryokuNixpkgs.qt6.qtimageformats
    ryokuNixpkgs.kdePackages.kirigami.unwrapped
  ];


  # Direct QML surfaces launched by the compositor do not inherit the
  # ryoku-shell systemd unit's QML import environment. Give them one Nix-native
  # entry point backed by the exact Quickshell and QML closure of this generation.
  ryokuQs = pkgs.writeShellScriptBin "ryoku-qs" ''
    export QML_IMPORT_PATH="${qmlRoot}:${qtQmlPath}''${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
    export QML2_IMPORT_PATH="${qmlRoot}:${qtQmlPath}''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"

    export QT_PLUGIN_PATH="${ryokuNixpkgs.qt6.qtimageformats}/lib/qt-6/plugins:${ryokuNixpkgs.qt6.qtbase}/lib/qt-6/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"

    exec ${ryokuQuickshell}/bin/qs "$@"
  '';

  optionalPkg = name:
    lib.optional (builtins.hasAttr name pkgs)
      (builtins.getAttr name pkgs);

  browserPackages =
    if cfg.browser == "chromium" then [ pkgs.chromium ]
    else if cfg.browser == "firefox" then [ pkgs.firefox ]
    else [ ];

  compositorSession = {
    hyprland = "hyprland";
    niri = "ryoku-niri";
    mango = "ryoku-mango";
  };

  optionalAppIds = [
    "prompt"
    "bash-edit"
    "fastfetch"
    "yazi"
    "cli-tools"
    "git-tools"
    "pavucontrol"
    "songrec"
    "openrgb"
    "upscale"
    "localsend"
    "gamescope"
    "gamemode"
    "mangohud"
    "vm"
    "docker"
    "flatpak"
    "go"
    "pytools"
    "mise"
  ];

  # Preserve the package/service set existing Ryoku-on-NixOS systems already
  # receive. The installer may opt into the additional supported tools without
  # silently adding them to established hosts on upgrade.
  defaultOptionalApps = [
    "prompt"
    "fastfetch"
    "yazi"
    "cli-tools"
    "pavucontrol"
    "songrec"
    "openrgb"
    "upscale"
    "gamescope"
    "gamemode"
    "mangohud"
    "vm"
    "docker"
    "mise"
  ];

  hasOptionalApp = id: lib.elem id cfg.optionalApps;

  optionalAppPackages =
    lib.optionals (hasOptionalApp "prompt") [ pkgs.starship ]
    ++ lib.optionals (hasOptionalApp "bash-edit") (optionalPkg "blesh")
    ++ lib.optionals (hasOptionalApp "fastfetch") [ pkgs.fastfetch ]
    ++ lib.optionals (hasOptionalApp "yazi") [ pkgs.yazi ]
    ++ lib.optionals (hasOptionalApp "cli-tools") [ pkgs.eza pkgs.bat pkgs.fzf pkgs.zoxide ]
    ++ lib.optionals (hasOptionalApp "git-tools") [ pkgs.lazygit ]
    ++ lib.optionals (hasOptionalApp "pavucontrol") [ pkgs.pavucontrol ]
    ++ lib.optionals (hasOptionalApp "songrec") (optionalPkg "songrec")
    ++ lib.optionals (hasOptionalApp "openrgb") (optionalPkg "openrgb")
    ++ lib.optionals (hasOptionalApp "upscale") [ ryokuWaifu2x ]
    ++ lib.optionals (hasOptionalApp "localsend") (optionalPkg "localsend")
    ++ lib.optionals (hasOptionalApp "gamescope") (optionalPkg "gamescope")
    ++ lib.optionals (hasOptionalApp "gamemode") (optionalPkg "gamemode")
    ++ lib.optionals (hasOptionalApp "mangohud") (optionalPkg "mangohud")
    ++ lib.optionals (hasOptionalApp "vm") [ pkgs.quickemu pkgs.qemu pkgs.spice-gtk pkgs.xorriso ]
    ++ lib.optionals (hasOptionalApp "go") [ pkgs.go ]
    ++ lib.optionals (hasOptionalApp "pytools") (optionalPkg "pipx")
    ++ lib.optionals (hasOptionalApp "mise") [ pkgs.mise ];

  optionalRuntime =
    lib.concatMap optionalPkg [
      "adw-gtk3"
      "gnome-themes-extra"
      "papirus-icon-theme"
      "bibata-cursors"

      "cliphist"
      "yt-dlp"
      "zenity"
      "tesseract"
      "zbar"
      "wf-recorder"
      "hyprsunset"
      "gammastep"
      "wtype"
      "libqalculate"
      "ddcutil"
      "gpu-screen-recorder"
    ];

  # NixOS cannot keep setuid executables in the immutable Nix store.
  # Expose only the privileged wrappers Ryoku needs through the shell's
  # otherwise store-only systemd PATH.
  ryokuPrivilegePath = pkgs.runCommand "ryoku-nixos-privilege-path" { } ''
    mkdir -p "$out/bin"

    ln -s       "${config.security.wrapperDir}/pkexec"       "$out/bin/pkexec"

    ln -s       "${config.security.wrapperDir}/sudo"       "$out/bin/sudo"
  '';

  runtimePackages = with pkgs; [
    # ─────────────────────────────────────────────────────────
    # Ryoku
    # ─────────────────────────────────────────────────────────

    ryokuBundle
    ryokuHelpers
    materializer
    ryokuNixSessionStart
    ryokuQylockLock
    ryokuSddmThemeApply
    ryokuSddmTheme
    ryokuPkgs.gpk
    ryokuSkwdPaper

    # ─────────────────────────────────────────────────────────
    # Standard userspace expected by Ryoku's shell snippets
    #
    # systemd `path = ...` creates an intentionally restricted
    # service PATH. Without these, even "bash", "sh", "pgrep",
    # "ip", "awk", etc. are invisible to QML Process{}.
    # ─────────────────────────────────────────────────────────

    bash
    coreutils
    getent
    findutils
    gnugrep
    gnused
    gawk
    procps
    iproute2
    util-linux
    systemd
    dbus
    which
    file
    less

    # Ryoku terminal / desktop baseline
    bash-completion
    gh
    desktop-file-utils
    sound-theme-freedesktop

    # ─────────────────────────────────────────────────────────
    # Compositor / shell
    # ─────────────────────────────────────────────────────────

    ryokuQs
    ryokuQuickshell
    ryokuHyprPlugins
    ryokuWmHyprland
    ryokuWmNiri
    ryokuWmMango
    ryokuNiri
    ryokuMango
    ryokuXwaylandSatellite

    # ─────────────────────────────────────────────────────────
    # Qt / QML
    # ─────────────────────────────────────────────────────────

    ryokuNixpkgs.qt6.qtdeclarative
    ryokuNixpkgs.qt6.qtmultimedia
    ryokuNixpkgs.qt6.qtwayland
    ryokuNixpkgs.qt6.qt5compat
    ryokuNixpkgs.qt6.qtsvg
    ryokuNixpkgs.qt6Packages.qt6ct
    ryokuNixpkgs.kdePackages.syntax-highlighting
    ryokuNixpkgs.kdePackages.kirigami.unwrapped

    # ─────────────────────────────────────────────────────────
    # Session / portals / secrets
    # ─────────────────────────────────────────────────────────

    gnome-keyring
    xdg-desktop-portal-gtk

    # ─────────────────────────────────────────────────────────
    # Desktop applications
    # ─────────────────────────────────────────────────────────

    kitty
    fish
    gtk3
    btop
    neovim
    tree-sitter
    nautilus
    nautilus-python

    # ─────────────────────────────────────────────────────────
    # Ryoport / local virtual machines
    # ─────────────────────────────────────────────────────────


    # ─────────────────────────────────────────────────────────
    # Ryoku command dependencies
    # ─────────────────────────────────────────────────────────

    hypridle
    wlsunset
    wlr-randr
    brightnessctl
    playerctl

    pipewire
    wireplumber
    pulseaudio

    mpvWithMpris
    wl-clipboard
    hyprpicker
    grim
    slurp
    cava

    jq
    imagemagick
    ryokuMatugen
    ffmpeg
    openssl
    nvibrant
    vulkan-tools
    ryokuCursorMaterial

    bibata-cursors
    vimix-cursors
    phinger-cursors
    apple-cursor

    # ─────────────────────────────────────────────────────────
    # Networking / hardware
    # ─────────────────────────────────────────────────────────

    networkmanager
    iwd
    iw
    bluez

    upower
    power-profiles-daemon

    # ─────────────────────────────────────────────────────────
    # Shell probes used by panels/settings
    # ─────────────────────────────────────────────────────────

    fd
    inxi
    lm_sensors
    pciutils
    usbutils

    # ─────────────────────────────────────────────────────────
    # Misc
    # ─────────────────────────────────────────────────────────

    python3

    # ii desktop/dock runtime helpers. Upstream installs these in its base
    # package set; on NixOS they live in the Ryoku service PATH instead.
    khal
    vdirsyncer
    translate-shell

    # Rashin setup/runtime prerequisites. Rashin itself remains
    # opt-in; these mirror the dependencies of the upstream package.
    nix
    uv
    nodejs
    gcc
    sqlite

    curl
    glib
    libnotify
    xdg-utils
  ]
  ++ lib.optional (ryokuPreviewSharePicker != null) ryokuPreviewSharePicker
  ++ optionalRuntime
  ++ optionalAppPackages
  ++ browserPackages;

  # Number of direct packages in the final NixOS system profile.
  #
  # This deliberately counts environment.systemPackages rather than
  # walking the Nix store closure. The latter includes dependencies and
  # gives misleadingly huge package totals in the Ryoku profile page.
  systemPackageCount =
    builtins.length (
      lib.unique (
        map toString config.environment.systemPackages
      )
    );

  nixIntegrationPackages =
    map
      (pkg: {
        name = lib.getName pkg;
        path = toString pkg;
      })
      (lib.unique (config.environment.systemPackages ++ runtimePackages));

  # The Ryoku service can be requested before the display manager's
  # compositor process has exported WAYLAND_DISPLAY into systemd.
  #
  # Rather than starting the daemon with WAYLAND_DISPLAY="", wait for
  # the manager environment to contain a real, live Wayland socket and
  # then exec the daemon with that exact session environment.
  ryokuSessionLauncher =
    pkgs.writeShellScript "ryoku-shell-session-launcher" ''
      set -euo pipefail

      # Ryoku's service has a deterministic Nix PATH containing its own
      # runtime dependencies. Launcher entries, however, may point to
      # arbitrary applications installed by the user or system.
      #
      # Preserve Ryoku's dependencies first, then expose the normal
      # NixOS/user executable locations so .desktop Exec commands work.
      export PATH="$PATH:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:$HOME/.local/bin"

      get_manager_env() {
        manager_env="$(
          ${pkgs.systemd}/bin/systemctl \
            --user show-environment 2>/dev/null || true
        )"

        printf '%s\n' "$manager_env" |
          ${pkgs.gnused}/bin/sed -n "s/^$1=//p" |
          ${pkgs.coreutils}/bin/head -n 1
      }

      attempts=0

      while [ "$attempts" -lt 300 ]; do
        runtime_dir="$(get_manager_env XDG_RUNTIME_DIR)"
        wayland_display="$(get_manager_env WAYLAND_DISPLAY)"

        if [ -z "$runtime_dir" ]; then
          runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
        fi

        wayland_socket="$runtime_dir/$wayland_display"

        # A compositor from the previous graphical session can leave its
        # Wayland socket inode behind after the listener is gone. `test -S`
        # alone therefore produces a false positive and starts Qt against a
        # dead display. Require an actual listening Unix socket before the
        # shell is allowed to start.
        if [ -n "$wayland_display" ] &&
           [ -S "$wayland_socket" ] &&
           ${pkgs.iproute2}/bin/ss -xlH |
             ${pkgs.gawk}/bin/awk -v socket="$wayland_socket" '
               $1 == "u_str" && $2 == "LISTEN" {
                 for (i = 1; i <= NF; i++) {
                   if ($i == socket) {
                     found = 1
                   }
                 }
               }
               END { exit found ? 0 : 1 }
             '
        then
          export XDG_RUNTIME_DIR="$runtime_dir"
          export WAYLAND_DISPLAY="$wayland_display"

          while IFS='=' read -r key value; do
            case "$key" in
              DISPLAY|WAYLAND_DISPLAY|XDG_*|*_SOCKET|*_INSTANCE_SIGNATURE)
                if [ -n "$value" ]; then
                  export "$key=$value"
                fi
                ;;
            esac
          done < <(systemctl --user show-environment)

          # Keep the service tied to the compositor socket it was started
          # against. The systemd user manager survives logout, so without this
          # the daemon survives the compositor too and repeatedly launches Qt
          # against a dead WAYLAND_DISPLAY until the next session imports its
          # environment.
          #
          # Run the daemon as our child and watch the actual listening socket.
          # Losing it means this graphical session is over: tear down the Ryoku
          # session target so every session-owned daemon stops cleanly. The next
          # compositor's bootstrap starts the target again after importing its
          # fresh environment.
          ${ryokuShell}/bin/ryoku-shell daemon &
          daemon_pid=$!

          cleanup_daemon() {
            if kill -0 "$daemon_pid" 2>/dev/null; then
              kill "$daemon_pid" 2>/dev/null || true
            fi
            wait "$daemon_pid" 2>/dev/null || true
          }

          trap 'cleanup_daemon; exit 0' TERM INT HUP
          trap cleanup_daemon EXIT

          while kill -0 "$daemon_pid" 2>/dev/null; do
            if ! ${pkgs.iproute2}/bin/ss -xlH |
              ${pkgs.gawk}/bin/awk -v socket="$wayland_socket" '
                $1 == "u_str" && $2 == "LISTEN" {
                  for (i = 1; i <= NF; i++) {
                    if ($i == socket) {
                      found = 1
                    }
                  }
                }
                END { exit found ? 0 : 1 }
              '
            then
              ${pkgs.systemd}/bin/systemctl                 --user --no-block stop ryoku-session.target >/dev/null 2>&1 || true

              exit 0
            fi

            ${pkgs.coreutils}/bin/sleep 0.1
          done

          status=0
          wait "$daemon_pid" || status=$?

          trap - EXIT
          exit "$status"
        fi

        attempts=$((attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      printf '%s\n' \
        "ryoku-shell: timed out waiting for the compositor Wayland socket" >&2

      exit 1
    '';

in
{
  imports = [
    (import ./gpu-passthrough.nix { inherit self; })
    ./release-identity.nix
    ./runtime-state-ownership.nix
    (import ./phone.nix { inherit ryokuNixpkgs; })
  ];

  options.programs.ryoku = {
    enable = lib.mkEnableOption "Ryoku desktop";

    binaryCache.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;

      description = ''
        Use Ryoku's public Ryotunes binary cache to avoid
        compiling the music application locally.
      '';
    };

    defaultCompositor = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "hyprland"
        "niri"
        "mango"
      ]);
      default = null;

      description = ''
        Graphical session Ryoku preselects at the display manager. All Ryoku
        compositor providers remain installed so the Hub can switch between
        them without a mutable package transaction. Null preserves the host's
        existing display-manager preference.
      '';
    };

    browser = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [
        "chromium"
        "firefox"
      ]);
      default = null;

      description = ''
        Browser Ryoku installs and uses as the fallback browser role. Null
        leaves browser ownership to the host and preserves existing systems.
      '';
    };

    optionalApps = lib.mkOption {
      type = lib.types.listOf (lib.types.enum optionalAppIds);
      default = defaultOptionalApps;

      description = ''
        Optional Ryoku applications and tool groups supplied by the NixOS
        integration. Required desktop contracts remain installed regardless of
        this list. The guided installer writes this option declaratively.
      '';
    };

    shell = lib.mkOption {
      type = lib.types.enum [
        "fish"
        "zsh"
      ];

      default = "fish";

      description = ''
        Interactive shell used by Ryoku on NixOS.

        Fish preserves Ryoku's upstream default. Zsh provides the same
        Starship prompt and core terminal integrations while leaving the
        user's ~/.zshrc untouched.
      '';
    };

    updateFlake = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";

      description = ''
        Flake whose Ryoku input is managed by the Hub update page.
        Only that input is advanced; unrelated Nix inputs are left alone.
      '';
    };

    updateInput = lib.mkOption {
      type = lib.types.str;
      default = "ryoku";

      description = ''
        Name of the Ryoku flake input updated by the NixOS update backend.
      '';
    };

  };

  config = lib.mkIf cfg.enable {
    # Nixpkgs wraps gsr-kms-server with the narrow capability upstream expects.
    # Installing gpu-screen-recorder as a plain package leaves that helper
    # unprivileged and forces an authentication prompt for every recording.
    programs.gpu-screen-recorder.enable = true;

    # Public binary cache for independently compiled Ryotunes releases.
    # Never distribute the private Cachix authentication token.
    nix.settings = lib.mkIf cfg.binaryCache.enable {
      substituters = lib.mkAfter [
        "https://ryotunes.cachix.org"
      ];

      trusted-public-keys = lib.mkAfter [
        "ryotunes.cachix.org-1:QNocajCsVm/IAMb8LPOWJi72XwqiexW9ec0UqeXLpGs="
      ];
    };

    # apple-cursor is part of Ryoku's cursor catalogue and is unfree in nixpkgs.
    nixpkgs.config.allowUnfreePredicate = lib.mkDefault (
      pkg: lib.getName pkg == "apple_cursor"
    );

    # Preserve Fish as Ryoku's upstream default while allowing Zsh as a
    # declarative NixOS alternative. Explicit per-user shell settings win.
    users.defaultUserShell =
      lib.mkOverride 900 (
        if cfg.shell == "fish"
        then pkgs.fish
        else pkgs.zsh
      );

    programs.fish = lib.mkIf (cfg.shell == "fish") {
      enable = true;
    };

    programs.zsh = lib.mkIf (cfg.shell == "zsh") {
      enable = true;

      shellAliases = lib.optionalAttrs (hasOptionalApp "cli-tools") {
        ls = "eza -lh --group-directories-first --icons=auto";
        lsa = "eza -lha --group-directories-first --icons=auto";
        lt = "eza --tree --level=2 --long --icons --git";
        lta = "eza --tree --level=2 --long --icons --git -a";
      };

      interactiveShellInit =
        lib.mkAfter (builtins.readFile ../shell/ryoku.zsh);
    };


    programs.hyprland = {
      enable = true;

      # Ryoku requires an exact compositor/plugin ABI match. Do not inherit
      # the host's Hyprland package, which may be older on NixOS stable.
      package = lib.mkForce ryokuHyprland;
      portalPackage = lib.mkForce ryokuHyprlandPortal;

      xwayland.enable = true;
    };

    programs.niri = {
      enable = true;
      package = lib.mkForce ryokuNiri;
    };

    xdg.portal = {
      enable = true;

      extraPortals = [
        pkgs.xdg-desktop-portal-gtk
        pkgs.xdg-desktop-portal-gnome
        pkgs.xdg-desktop-portal-wlr
      ];

      config.hyprland.default = [
        "hyprland"
        "gtk"
      ];

      config.niri = {
        default = [
          "gnome"
          "gtk"
        ];

        "org.freedesktop.impl.portal.FileChooser" = [
          "gtk"
        ];
      };

      config.mango = {
        default = [
          "gtk"
        ];

        "org.freedesktop.impl.portal.Secret" = [
          "gnome-keyring"
        ];

        "org.freedesktop.impl.portal.ScreenCast" = [
          "wlr"
        ];

        "org.freedesktop.impl.portal.ScreenShot" = [
          "wlr"
        ];

        "org.freedesktop.impl.portal.Inhibit" = [
          "none"
        ];
      };
    };

    # xdg-desktop-portal-gnome disables its screencast backend when it inherits
    # Ryoku's global GDK_BACKEND override under Niri. Keep the session setting
    # intact and remove it only from the GNOME portal process.
    systemd.user.services.xdg-desktop-portal-gnome = {
      overrideStrategy = "asDropin";
      serviceConfig.UnsetEnvironment = "GDK_BACKEND";
    };

    # Export localized XDG user directories into the systemd user-manager
    # environment so Ryoku does not invent ~/Pictures or ~/Downloads on systems
    # whose real directories have localized names.
    environment.etc."systemd/user-environment-generators/60-ryoku-xdg-dirs" = {
      mode = "0755";

      text = ''
        #!${pkgs.runtimeShell}
        set -eu

        [ -f "$HOME/.config/user-dirs.dirs" ] || exit 0

        for dir in PICTURES DOWNLOAD DOCUMENTS MUSIC VIDEOS DESKTOP PUBLICSHARE TEMPLATES; do
          path="$(${pkgs.xdg-user-dirs}/bin/xdg-user-dir "$dir" 2>/dev/null)" || continue
          [ -n "$path" ] || continue
          printf 'XDG_%s_DIR=%s\n' "$dir" "$path"
        done
      '';
    };

    # Palette Bridge is packaged declaratively, but enablement is intentionally
    # user state: the Ryogami settings page exposes Enable/Disable and upstream
    # implements that through `systemctl --user enable --now`.
    #
    # NixOS' systemd.user.services.wantedBy creates stateless Nix-owned wants
    # links and does not emit an [Install] section, so define the immutable unit
    # file directly under /etc/systemd/user. The user may then enable/disable
    # this one service normally without being able to replace its definition.
    systemd.user.units."ryoku-palette-bridge.service".text = ''
      [Unit]
      Description=Ryoku wallpaper palette event bridge
      PartOf=ryoku-session.target
      After=ryoku-session.target ryoku-shell.service

      # colors.json can legitimately be absent briefly after a cleared cache or
      # first login. Keep retrying until the shell authors a valid palette
      # instead of permanently hitting systemd's default start-rate limit.
      StartLimitIntervalSec=0

      [Service]
      Type=simple
      ExecStart=${ryokuPaletteBridge}/bin/ryoku-palette-bridge
      Restart=on-failure
      RestartSec=5
      Slice=session.slice

      [Install]
      WantedBy=ryoku-session.target
    '';

    # NixOS 26.05 creates the pkexec wrapper automatically when Polkit is
    # enabled. Newer nixpkgs exposes enablePkexecWrapper separately.
    # Feature-detect that newer option so this module evaluates on both.
    #
    # Ryoku NixOS privileged helper policy:
    # these grants use immutable Nix-store paths instead of Arch's
    # /usr/bin paths. Mutable NetworkManager/Docker helpers are not
    # authorized here; they receive Nix-aware implementations separately.
    security.polkit = {
      enable = true;

      extraConfig = lib.mkAfter ''
      polkit.addRule(function (action, subject) {
          if (action.id === "org.freedesktop.systemd1.manage-units" &&
              action.lookup("unit") === "bluetooth.service" &&
              subject.isInGroup("wheel")) {
              return polkit.Result.YES;
          }
      });

      polkit.addRule(function (action, subject) {
          if (action.id === "org.freedesktop.policykit.exec" &&
              action.lookup("program") === "${ryokuHelpers}/bin/ryoku-power" &&
              subject.local &&
              subject.active &&
              subject.isInGroup("wheel")) {
              return polkit.Result.YES;
          }
      });

      polkit.addRule(function (action, subject) {
          if (action.id === "org.freedesktop.policykit.exec" &&
              action.lookup("program") === "${ryokuHelpers}/bin/ryoku-game-tune" &&
              subject.local &&
              subject.active &&
              subject.isInGroup("wheel")) {
              return polkit.Result.YES;
          }
      });

      polkit.addRule(function (action, subject) {
          var program = action.lookup("program");

          if (action.id === "org.freedesktop.policykit.exec" &&
              (program === "${ryokuHelpers}/bin/ryoku-wifi-powersave" ||
               program === "/run/current-system/sw/bin/ryoku-wifi-powersave") &&
              subject.local &&
              subject.active &&
              subject.isInGroup("wheel")) {
              return polkit.Result.YES;
          }
      });


      // Ryoku NixOS system bridge authorization.
      //
      // Mutable operations enter only through immutable store paths.
      polkit.addRule(function (action, subject) {
          if (action.id !== "org.freedesktop.policykit.exec" ||
              !subject.local ||
              !subject.active ||
              !subject.isInGroup("wheel")) {
              return;
          }

          var program = action.lookup("program");

          if (program === "${ryokuSystemBridge}/bin/ryoku-dns" ||
              program === "${ryokuSystemBridge}/bin/ryoku-wifi-backend" ||
              program === "${ryokuSystemBridge}/bin/ryoku-wifi-regdom" ||
              program === "${ryokuSystemBridge}/bin/ryoku-docker") {
              return polkit.Result.YES;
          }
      });

      // Ryoku NixOS SDDM theme activation.
      //
      // SDDM configuration remains declarative. Settings may only
      // replace the mutable theme payload through this helper.
      polkit.addRule(function (action, subject) {
          var program = action.lookup("program");

          if (action.id === "org.freedesktop.policykit.exec" &&
              (program === "${ryokuSddmThemeApply}/bin/ryoku-sddm-theme-apply" ||
               program === "/run/current-system/sw/bin/ryoku-sddm-theme-apply") &&
              subject.local &&
              subject.active &&
              subject.isInGroup("wheel")) {
              return polkit.Result.YES;
          }
      });

      '';
    } // lib.optionalAttrs (
      lib.hasAttrByPath
        [ "security" "polkit" "enablePkexecWrapper" ]
        options
    ) {
      enablePkexecWrapper = lib.mkDefault true;
    };
    services.gnome.gnome-keyring.enable = true;

    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;

      alsa = {
        enable = true;
        support32Bit = true;
      };

      pulse.enable = true;
      wireplumber.enable = true;
    };

    # Ryoku's networking surface talks to NetworkManager directly.
    # Use mkDefault so hosts with an intentional alternative network
    # stack can still override this.
    networking.networkmanager.enable = lib.mkDefault true;


    # Ryoku NixOS mutable network bridge.
    #
    # Nix owns the /etc path names. Runtime choices live under
    # /var/lib/ryoku rather than rewriting generated NixOS files.
    systemd.tmpfiles.rules = lib.mkAfter [
      "d /var/lib/ryoku 0755 root root -"
      "d /var/lib/ryoku/network 0755 root root -"
      "f /var/lib/ryoku/network/wifi-backend.conf 0644 root root -"
      "f /var/lib/ryoku/network/dns.conf 0644 root root -"
      "f /var/lib/ryoku/network/regdom 0644 root root -"
      "f /var/lib/ryoku/network/iwd.conf 0644 root root -"
    ];

    environment.etc."NetworkManager/conf.d/90-ryoku-wifi-backend.conf" = {
      source = "/var/lib/ryoku/network/wifi-backend.conf";
      mode = "direct-symlink";
    };

    environment.etc."NetworkManager/conf.d/91-ryoku-dns.conf" = {
      source = "/var/lib/ryoku/network/dns.conf";
      mode = "direct-symlink";
    };

    environment.etc."iwd/main.conf" = {
      source = "/var/lib/ryoku/network/iwd.conf";
      mode = "direct-symlink";
    };

    # iwd is available as Ryoku's alternative NetworkManager backend,
    # but NixOS does not statically select or start it.
    services.dbus.packages = lib.mkAfter [
      pkgs.iwd
    ];

    systemd.packages = lib.mkAfter [
      pkgs.iwd
    ];

    # Re-apply a persisted regulatory domain before networking.
    # With no configured country this is intentionally a no-op.
    systemd.services.ryoku-network-regdom = {
      description =
        "Restore Ryoku wireless regulatory domain";

      wantedBy = [
        "network-pre.target"
      ];

      before = [
        "NetworkManager.service"
        "iwd.service"
        "wpa_supplicant.service"
      ];

      after = [
        "systemd-modules-load.service"
        "systemd-tmpfiles-setup.service"
      ];

      serviceConfig = {
        Type = "oneshot";

        ExecStart =
          "${ryokuSystemBridge}/bin/ryoku-wifi-regdom apply";
      };
    };

    # NetworkManager reads Ryoku's persisted override itself.
    # This unit merely makes sure only the selected supplicant owns
    # the radio after boot.
    systemd.services.ryoku-network-backend = {
      description =
        "Reconcile Ryoku NetworkManager Wi-Fi backend";

      wantedBy = [
        "multi-user.target"
      ];

      wants = [
        "NetworkManager.service"
      ];

      after = [
        "NetworkManager.service"
      ];

      serviceConfig = {
        Type = "oneshot";

        ExecStart =
          "${ryokuSystemBridge}/bin/ryoku-wifi-backend reconcile";
      };
    };

    # NixOS owns Docker installation. Ryoku may start it lazily for
    # its tightly-scoped Cobalt container workflow.
    virtualisation.docker = {
      enable = lib.mkDefault (hasOptionalApp "docker");
      enableOnBoot = lib.mkDefault false;
    };

    services.flatpak.enable = lib.mkDefault (hasOptionalApp "flatpak");

    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;

      settings = {
        General = {
          Experimental = lib.mkDefault true;
          FastConnectable = lib.mkDefault true;
          JustWorksRepairing = lib.mkDefault "always";
          MultiProfile = lib.mkDefault "multiple";
        };

        Policy = {
          AutoEnable = lib.mkDefault true;
        };
      };
    };

    # BlueZ needs a persistent session agent for HID devices that confirm a
    # numeric passkey. Upstream ships this as a user unit around bluetoothctl;
    # NixOS owns bluetoothd as a system service, so the user agent only needs
    # immutable executable paths and restart semantics here.
    systemd.user.services.ryoku-bt-agent = {
      description = "Ryoku Bluetooth pairing agent (BlueZ default agent)";

      wantedBy = [
        "default.target"
      ];

      unitConfig = {
        ConditionPathExistsGlob = "/sys/class/bluetooth/*";
      };

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.writeShellScript "ryoku-bt-agent" ''
          set -euo pipefail
          ${pkgs.coreutils}/bin/tail -f /dev/null | \
            ${pkgs.bluez}/bin/bluetoothctl --agent KeyboardDisplay
        ''}";
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "session.slice";
      };
    };

    services.upower.enable = lib.mkDefault true;
    services.power-profiles-daemon.enable = lib.mkDefault true;

    boot.kernelModules = lib.mkAfter [
      "i2c-dev"
      "uinput"
    ];

    boot.extraModprobeConfig = lib.mkAfter ''
      options snd_hda_intel power_save=0 power_save_controller=N

      options btusb enable_autosuspend=0
      options bluetooth disable_ertm=1
    '';

    users.groups.i2c = { };

    services.udev.packages = lib.mkAfter [
      ryokuUdevRules
    ];

    # Ryoku's clamshell daemon is the only component that inhibits
    # lid suspend, and only while on AC with an external display.
    environment.etc."systemd/logind.conf.d/10-ryoku-lid.conf".text = ''
      [Login]
      HandleLidSwitch=suspend
      HandleLidSwitchExternalPower=suspend
      HandleLidSwitchDocked=ignore
      InhibitDelayMaxSec=15
    '';

    # Seed the mutable SDDM payload once. Generation switches preserve a
    # user-selected RyoStore theme; a missing/broken state falls back to Orbital.
    system.activationScripts.ryokuSddmTheme = ''
      if [ ! -f /var/lib/ryoku/sddm-theme/Main.qml ]; then
        ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/ryoku
        ${pkgs.coreutils}/bin/rm -rf /var/lib/ryoku/sddm-theme

        ${pkgs.coreutils}/bin/cp -a \
          ${ryokuDesktopData}/share/ryoku/lockscreen/qylock/themes/clockwork/orbital \
          /var/lib/ryoku/sddm-theme

        ${pkgs.coreutils}/bin/chown -R root:root /var/lib/ryoku/sddm-theme
        ${pkgs.coreutils}/bin/chmod -R a+rX /var/lib/ryoku/sddm-theme
      fi
    '';

    environment.systemPackages =
      runtimePackages;


    # A fresh installer can choose the initial compositor while all three
    # remain available for runtime switching. Manual integrations leave this
    # null and keep the host's existing display-manager preference.
    services.displayManager.defaultSession =
      lib.mkIf (cfg.defaultCompositor != null)
        (lib.mkOverride 900 compositorSession.${cfg.defaultCompositor});

    # Supply a greeter on No Desktop installs, preserving another login manager.
    services.displayManager.sessionPackages = [
      ryokuNiriSession
      ryokuMangoSession
    ];

    services.displayManager.sddm = {
      enable = lib.mkDefault (!(lib.any
        (path: lib.attrByPath path false config)
        [
          (if lib.hasAttrByPath [ "services" "displayManager" "gdm" "enable" ] options
           then [ "services" "displayManager" "gdm" "enable" ]
           else [ "services" "xserver" "displayManager" "gdm" "enable" ])
          [ "services" "xserver" "displayManager" "lightdm" "enable" ]
          [ "services" "displayManager" "ly" "enable" ]
          [ "services" "displayManager" "cosmic-greeter" "enable" ]
          [ "services" "greetd" "enable" ]
        ]));

      theme = lib.mkIf config.services.displayManager.sddm.enable
        (lib.mkOverride 900 "ryoku");

      # A No Desktop NixOS install has no Xserver for SDDM to run on.
      # Ryoku is Wayland-native, so when SDDM is active without Xserver,
      # supply its Wayland greeter backend as the default. An explicit user
      # choice still wins because this remains mkDefault.
      wayland.enable = lib.mkIf
        (config.services.displayManager.sddm.enable && !config.services.xserver.enable)
        (lib.mkDefault true);

      extraPackages = lib.mkIf config.services.displayManager.sddm.enable [
        ryokuSddmTheme
        pkgs.qt6.qt5compat
        pkgs.qt6.qtdeclarative
        pkgs.qt6.qtmultimedia
        pkgs.qt6.qtsvg
      ];
    };

    # SDDM 0.21 can treat a crashed Wayland greeter as a successful login and
    # leave the machine on an empty VT. The upstream guard waits until SDDM has
    # no greeter or session helper for 20 seconds, then performs a bounded
    # display-manager restart. Keep the recovery behaviour while leaving NixOS
    # in sole ownership of the compositor and unit definitions.
    systemd.services.ryoku-greeter-guard = lib.mkIf
      (config.services.displayManager.sddm.enable &&
       config.services.displayManager.sddm.wayland.enable) {
        description = "Ryoku login screen guard";
        wantedBy = [ "graphical.target" ];
        wants = [ "display-manager.service" ];
        after = [ "display-manager.service" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${ryokuGreeterGuard}/bin/ryoku-greeter-guard";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };

    # NixOS uses Ryoku's Nix-only update backend; the Arch transaction stays disabled.
    # Session scope also covers Hub instances launched directly.
    environment.sessionVariables = {
      RYOKU_NIX_SYSTEM_BRIDGE = "1";
      RYOKU_NIX_INTEGRATION = "/etc/ryoku/nix-integration.json";
      RYOKU_DOCKER_HOST_MANAGED = "1";
      RYOKU_DEFAULT_BROWSER = if cfg.browser == null then "" else cfg.browser;
      RYOKU_UPDATE_BACKEND = "nix";
      RYOKU_I18N_DIR = "${ryokuDesktopData}/share/ryoku/i18n";
      RYOKU_NOMARCHY_SOURCE = "${ryokuDesktopData}/share/ryoku/nomarchy";
      RYOKU_NIX_FLAKE = cfg.updateFlake;
      RYOKU_NIX_INPUT = cfg.updateInput;
      RYOKU_NIX_SUDO =
        "${config.security.wrapperDir}/sudo";
      RYOKU_SDDM_THEME_APPLY =
        "${ryokuSddmThemeApply}/bin/ryoku-sddm-theme-apply";
      RYOKU_SYSTEM_UPDATES_EXTERNAL = "0";
      RYOKU_QYLOCK_INSTALLER =
        "${ryokuDesktopData}/share/ryoku/lockscreen/install-qylock";
      RYOKU_QYLOCK_BUNDLE =
        "${ryokuDesktopData}/share/ryoku/lockscreen/qylock";

      # Hyprland plugin binaries are ABI-sensitive generation state.
      # Hub may configure them, but Nix owns compilation and package paths.
      RYOKU_HYPR_PLUGINS_MANAGED = "nix";
      RYOKU_HYPR_PLUGIN_DIR =
        "${ryokuHyprPlugins}/lib/hyprland/plugins";

      # Ryowalls and Ryoshot normally use Arch's /usr/share
      # model path. Point them at the immutable nixpkgs payload.
      RYOKU_WAIFU2X_MODELS = waifu2xModels;
    };

    environment.etc."ryoku/nix-system-package-count".text =
      "${toString systemPackageCount}\n";

    environment.etc."ryoku/nix-integration.json".text = builtins.toJSON {
      schema = 1;
      version = self.lib.version;
      flake = cfg.updateFlake;
      host = config.networking.hostName;
      input = cfg.updateInput;
      configBase = "${ryokuDesktopData}/share/ryoku/config";
      i18nDir = "${ryokuDesktopData}/share/ryoku/i18n";
      browser = if cfg.browser == null then "" else cfg.browser;
      defaultCompositor = if cfg.defaultCompositor == null then "" else cfg.defaultCompositor;
      shell = cfg.shell;
      optionalApps = cfg.optionalApps;
      packages = nixIntegrationPackages;
    };

    fonts.packages =
      [
        pkgs.rubik
        pkgs.readexpro
        pkgs.inter
        pkgs.fraunces
        spaceGrotesk
        ryokuMapleMonoNF

        pkgs.nerd-fonts.jetbrains-mono
        pkgs.nerd-fonts.space-mono
        pkgs.nerd-fonts.fira-code
        pkgs.nerd-fonts.hack
        pkgs.noto-fonts
        pkgs.noto-fonts-color-emoji
      ]
      ++ optionalPkg "noto-fonts-cjk-sans"
      ++ optionalPkg "material-symbols";

    systemd.user.targets.ryoku-session = {
      description = "Ryoku graphical session";

      wants = [
        "graphical-session-pre.target"
        "xdg-desktop-autostart.target"
      ];

      after = [
        "graphical-session-pre.target"
      ];

      before = [
        "graphical-session.target"
        "xdg-desktop-autostart.target"
      ];

      bindsTo = [
        "graphical-session.target"
      ];
    };

    # Rashin is optional at the application level: the service
    # exists on every Ryoku system, while `serve --if-enabled`
    # exits immediately until the user enables Rashin.
    # Work around the BlueZ A2DP reconnect regression after
    # the user's PipeWire/WirePlumber session is available.
    # Hypridle is compositor-neutral. Upstream ryoku-idle now renders its
    # policy from power.json and reaches display power through the WM seam.
    # NixOS keeps only the process lifecycle declarative; policy remains owned
    # by Ryoku and is editable from the Hub.
    systemd.user.services.ryoku-idle = {
      description = "Ryoku idle policy daemon";

      wantedBy = [
        "ryoku-session.target"
      ];

      partOf = [
        "ryoku-session.target"
      ];

      requires = [
        "ryoku-materialize.service"
      ];

      after = [
        "ryoku-materialize.service"
      ];

      path = runtimePackages;

      restartTriggers = [
        materializer
      ];

      serviceConfig = {
        # ryoku-idle renders the compositor-neutral policy first, then execs
        # hypridle. The public wrapper routes Hub/autostart changes back through
        # this systemd-owned unit instead of spawning a second daemon.
        ExecStart =
          "${ryokuHelpers}/libexec/ryoku-idle start";

        Restart = "on-failure";
        RestartSec = "1s";
      };
    };

    systemd.user.services.ryoku-clamshell = {
      description = "Ryoku clamshell policy daemon";

      wantedBy = [
        "ryoku-session.target"
      ];

      partOf = [
        "ryoku-session.target"
      ];

      requires = [
        "ryoku-materialize.service"
      ];

      after = [
        "ryoku-session.target"
        "ryoku-materialize.service"
      ];

      path = [ ryokuPrivilegePath ] ++ runtimePackages;

      unitConfig = {
        ConditionEnvironment = "WAYLAND_DISPLAY";
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      serviceConfig = {
        ExecStart =
          "${ryokuHelpers}/bin/ryoku-clamshell daemon";

        Restart = "on-failure";
        RestartSec = "2s";
        TimeoutStopSec = "5s";
        Slice = "session.slice";
      };
    };

    # Ryoku's 10-band PipeWire equalizer is started on demand by
    # `ryoku-eq`. The generated filter configuration remains user state,
    # while the service executable itself stays immutable in the Nix store.
    systemd.user.services.ryoku-eq = {
      description = "Ryoku equalizer (PipeWire smart filter)";

      after = [ "pipewire.service" ];
      partOf = [ "pipewire.service" ];

      unitConfig.ConditionPathExists = "%t/ryoku/eq/filter-chain.conf";

      serviceConfig = {
        Type = "simple";
        ExecStart =
          "${pkgs.pipewire}/bin/pipewire -c %t/ryoku/eq/filter-chain.conf";
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "session.slice";
      };
    };

    systemd.user.services.ryoku-bluetooth-reset = {
      description =
        "Reset the Bluetooth controller once the Ryoku audio session is ready";

      wantedBy = [
        "ryoku-session.target"
      ];

      partOf = [
        "ryoku-session.target"
      ];

      after = [
        "wireplumber.service"
      ];

      unitConfig = {
        ConditionPathExistsGlob = "/sys/class/bluetooth/*";
      };

      serviceConfig = {
        Type = "oneshot";
        ExecStart =
          "${pkgs.systemd}/bin/systemctl restart bluetooth.service";
        TimeoutStartSec = 30;
      };
    };

    systemd.user.services.ryoku-rashin = {
      description = "Ryoku Rashin local agent OS daemon and dashboard";

      wantedBy = [
        "default.target"
      ];

      path = runtimePackages;

      environment = {
        RYOKU_RASHIN_SKILLS =
          "${ryokuRashin}/share/ryoku/skills";
        RYOKU_UPDATE_BACKEND = "nix";
      };

      unitConfig = {
        StartLimitIntervalSec = 0;
      };

      serviceConfig = {
        ExecStart =
          "${ryokuRashin}/bin/ryoku-rashin serve --if-enabled";

        Restart = "on-failure";
        RestartSec = 2;
        NoNewPrivileges = true;
      };
    };

    # Refresh the AI usage caches consumed by Ryoku's bar.
    #
    # These mirror upstream's ryoku-ai-usage.service/timer, but
    # point directly at immutable Nix-store helpers instead of
    # Arch's /usr/bin paths.
    systemd.user.services.ryoku-ai-usage = {
      description = "Ryoku AI usage collectors";

      serviceConfig = {
        Type = "oneshot";

        ExecStart = [
          "-${ryokuDesktopData}/bin/claude-usage"
          "-${ryokuDesktopData}/bin/codex-usage"
          "-${ryokuDesktopData}/bin/opencode-usage"
        ];
      };
    };

    systemd.user.timers.ryoku-ai-usage = {
      description = "Ryoku AI usage collector schedule";

      wantedBy = [
        "timers.target"
      ];

      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "10min";
        Persistent = true;
      };
    };

    # Keep Ryoku's materialized user configuration in lockstep with
    # the active Nix generation. Upstream intentionally materializes
    # writable base files into ~/.config rather than running them
    # directly from the package store.
    systemd.user.services.ryoku-materialize = {
      description = "Materialize the current Ryoku desktop generation";

      before = [
        "ryoku-shell.service"
      ];

      wantedBy = [
        "ryoku-session.target"
      ];

      restartTriggers = [
        materializer
      ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        # Materialization rewrites the live Ryoku config tree. Hyprland
        # normally watches its config and reloads on every change, which can
        # expose a partially materialized tree during `nixos-rebuild switch`.
        # Quiesce autoreload for the transaction, then reload exactly once.
        ExecStart = pkgs.writeShellScript "ryoku-materialize-live" ''
          set -eu

          reload_wm=0

          if command -v ryoku >/dev/null 2>&1 &&
             ryoku wm act config.autoreload off >/dev/null 2>&1
          then
            reload_wm=1
          fi

          cleanup() {
            if [ "$reload_wm" -eq 1 ]; then
              ryoku wm act config.reload config-only >/dev/null 2>&1 || true
              ryoku wm act config.autoreload on >/dev/null 2>&1 || true
            fi
          }

          trap cleanup EXIT

          ${materializer}/bin/ryoku-materialize
        '';

      };
    };

    # Ryogami owns wallpaper cataloguing, palette application,
    # live wallpapers and the wallpaper picker in current Ryoku.
    #
    # Upstream installs /usr/bin/ryogami and a user unit under
    # /usr/lib/systemd/user. NixOS owns both declaratively.
    # ─────────────────────────────────────────────────────────
    # Ryotunes
    #
    # Ryotunes 2.5 uses a socket-activated playback daemon and
    # native Quickshell client. Upstream enables the user socket
    # through a package preset; NixOS owns both units here.
    # ─────────────────────────────────────────────────────────

    systemd.user.sockets.ryotunesd = {
      description = "Ryotunes playback daemon socket";

      wantedBy = [
        "sockets.target"
      ];

      socketConfig = {
        ListenStream = "%t/ryotunes/ryotunesd.sock";
        SocketMode = "0600";
        DirectoryMode = "0700";
      };
    };

    systemd.user.services.ryotunesd = {
      description = "Ryotunes playback daemon";

      # ryotunesd launches ryotunes-qml by command name. Keep the
      # Ryotunes package first, then expose the normal Ryoku runtime.
      path = [ ryokuRyotunes ] ++ runtimePackages;

      # Upstream's daemon launches the native frontend with
      # Command::new("ryotunes-qml"), and that Quickshell client in turn
      # launches normal desktop helpers such as sh, ryostore, zenity and
      # xdg-open.
      #
      # Keep Ryotunes itself deterministic and first in PATH, then expose the
      # active NixOS system profile just like an ordinary graphical session.
      # This preserves upstream's desktop-command model without baking FHS
      # paths or mutable tool copies into the package.
      environment = {
        RUST_LOG = "warn";
      };

      after = [
        "graphical-session.target"
      ];

      requires = [
        "ryotunesd.socket"
      ];

      serviceConfig = {
        ExecStart = "${ryokuRyotunes}/bin/ryotunesd";
        Restart = "on-failure";
        RestartSec = "2s";
      };
    };

    systemd.user.services.ryogami = {
      description = "Ryogami wallpaper daemon";

      wantedBy = [
        "ryoku-session.target"
      ];

      partOf = [
        "ryoku-session.target"
      ];

      requires = [
        "ryoku-materialize.service"
      ];

      after = [
        "ryoku-materialize.service"
      ];

      # The daemon shells out to the normal Ryoku desktop tools.
      path = runtimePackages;

      environment = {
        RYOKU_WAIFU2X_MODELS = waifu2xModels;

        MALLOC_CONF =
          "narenas:2,background_thread:true,dirty_decay_ms:5000,muzzy_decay_ms:5000";

        QT_MEDIA_BACKEND = "ffmpeg";
        QT_FFMPEG_DECODING_HW_DEVICE_TYPES = ",";

        QML_IMPORT_PATH =
          "${ryokuRyogami}/lib/qt-6/qml:${qmlRoot}:${qtQmlPath}";

        QML2_IMPORT_PATH =
          "${ryokuRyogami}/lib/qt-6/qml:${qmlRoot}:${qtQmlPath}";
      };

      unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      serviceConfig = {
        ExecStart =
          "${ryokuRyogami}/bin/ryogami";

        Restart = "always";
        RestartSec = 2;

        # Match upstream: the renderer/helper processes may finish
        # independently when Ryogami itself is reloaded.
        KillMode = "process";
        Slice = "session.slice";
      };
    };

    systemd.user.services.ryoku-shell = {
      restartTriggers = [ qylockMaterializer ];

      requires = [
        "ryoku-materialize.service"
      ];
      description = "Ryoku shell daemon";

      wantedBy = [
        "ryoku-session.target"
      ];

      partOf = [
        "ryoku-session.target"
      ];

      after = [
        "ryoku-materialize.service"
      ];

      path = [ ryokuPrivilegePath ] ++ runtimePackages;

      environment = {

        RYOKU_DOCKER_HOST_MANAGED = "1";

        RYOKU_NIX_SYSTEM_BRIDGE = "1";
        RYOKU_NIX_INTEGRATION = "/etc/ryoku/nix-integration.json";
        RYOKU_DEFAULT_BROWSER = if cfg.browser == null then "" else cfg.browser;
        RYOKU_NOMARCHY_SOURCE = "${ryokuDesktopData}/share/ryoku/nomarchy";
        RYOKU_POLKIT_AGENT = "1";
        RYOKU_SYSTEMD_RUN = "${pkgs.systemd}/bin/systemd-run";

        # NixOS owns system generations. The Hub may advance only the
        # configured Ryoku flake input through the Nix update backend.
        RYOKU_UPDATE_BACKEND = "nix";
        RYOKU_NIX_FLAKE = cfg.updateFlake;
        RYOKU_NIX_INPUT = cfg.updateInput;
        RYOKU_NIX_SUDO =
          "${config.security.wrapperDir}/sudo";
        RYOKU_SDDM_THEME_APPLY =
          "${ryokuSddmThemeApply}/bin/ryoku-sddm-theme-apply";
        RYOKU_SYSTEM_UPDATES_EXTERNAL = "0";
      RYOKU_QYLOCK_INSTALLER =
        "${ryokuDesktopData}/share/ryoku/lockscreen/install-qylock";
      RYOKU_QYLOCK_BUNDLE =
        "${ryokuDesktopData}/share/ryoku/lockscreen/qylock";

      # Hyprland plugin binaries are ABI-sensitive generation state.
      # Hub may configure them, but Nix owns compilation and package paths.
      RYOKU_HYPR_PLUGINS_MANAGED = "nix";
      RYOKU_HYPR_PLUGIN_DIR =
        "${ryokuHyprPlugins}/lib/hyprland/plugins";
        RYOKU_WAIFU2X_MODELS = waifu2xModels;

        QT_MEDIA_BACKEND = "ffmpeg";
        QT_FFMPEG_DECODING_HW_DEVICE_TYPES = ",";

        QT_PLUGIN_PATH =
          "${ryokuNixpkgs.qt6.qtimageformats}/lib/qt-6/plugins:${ryokuNixpkgs.qt6.qtbase}/lib/qt-6/plugins";

        QML_IMPORT_PATH =
          "${qmlRoot}:${qtQmlPath}";

        QML2_IMPORT_PATH =
          "${qmlRoot}:${qtQmlPath}";
      };

      unitConfig = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      serviceConfig = {
        ExecStartPre = [
          "-${ryokuShell}/bin/ryoku-shell quit"

          # Ryoku Shell is the session's notification server. A Mako process
          # from an older Nix generation can survive the package removal and
          # keep org.freedesktop.Notifications, making Ryoku styling and DND
          # appear broken after an in-place update. Retire both a user unit and
          # any surviving standalone process before Quickshell starts.
          "-${pkgs.systemd}/bin/systemctl --user stop mako.service"
          "-${pkgs.procps}/bin/pkill -f /bin/mako([[:space:]]|$)"

          "${qylockMaterializer}"
          "${ryokuHelpers}/bin/ryoku-qylock-activate"
        ];

        ExecStart =
          ryokuSessionLauncher;

        ExecStop =
          "${ryokuHelpers}/bin/ryoku-qylock-activate --prepare-stop";

        ExecStartPost =
          "-${ryokuHelpers}/bin/ryoku-power-cutover qylock-guards-stop";

        TimeoutStartSec = 0;
        TimeoutStopSec = 0;

        Restart = "always";
        RestartSec = 2;

        # User applications are launched into independent app.slice scopes,
        # so the shell can safely own and clean up its complete process tree.
        # This prevents stale shell helpers from surviving generation changes.
        KillMode = "control-group";
        Slice = "session.slice";
      };
    };
  };
}
