{ pkgs, ryoku }:

pkgs.writeShellApplication {
  name = "ryoku-materialize";

  runtimeInputs = with pkgs; [
    coreutils
    findutils
    jq
    systemd
  ];

  text = ''
    base="${ryoku.desktopData}/share/ryoku/config"
    qml="${ryoku.qml}/lib/qt-6/qml"

    config_home="''${XDG_CONFIG_HOME:-$HOME/.config}"
    user_units="$config_home/systemd/user"
    state="''${XDG_STATE_HOME:-$HOME/.local/state}/ryoku/nix"
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$state/backups/$stamp"

    mkdir -p "$state"

    # ----------------------------------------------------------
    # First deployment backup
    #
    # Derive the backup set from the packaged config itself.
    # This keeps the backup complete when upstream adds another
    # application config instead of maintaining a second list here.
    # ----------------------------------------------------------

    if [ ! -e "$state/initial-backup-complete" ]; then
      mkdir -p "$backup/config"

      while IFS= read -r -d "" packaged; do
        name="''${packaged##*/}"
        current="$config_home/$name"

        if [ -e "$current" ] || [ -L "$current" ]; then
          cp -a -- "$current" "$backup/config/"
        fi
      done < <(
        find "$base" \
          -mindepth 1 \
          -maxdepth 1 \
          -print0
      )

      # Ryoku also owns these user-local QML module names. They live
      # outside XDG_CONFIG_HOME, so preserve a previous deployment
      # before replacing the modules with Nix-store links.
      current_qml="$HOME/.local/lib/qt6/qml/Ryoku"

      if [ -e "$current_qml" ] || [ -L "$current_qml" ]; then
        mkdir -p "$backup/local-qml"
        cp -a -- "$current_qml" "$backup/local-qml/"
      fi

      # Preserve any existing Ryoku user units before NixOS takes
      # ownership of these names.
      for unit in \
        ryoku-session.target \
        hyprland-session.target \
        ryoku-shell.service \
        ryogami.service \
        ryoku-rashin.service \
        ryoku-ai-usage.service \
        ryoku-ai-usage.timer \
        ryoku-palette-bridge.service
      do
        current="$user_units/$unit"

        if [ -e "$current" ] || [ -L "$current" ]; then
          mkdir -p "$backup/systemd-user"
          cp -a -- "$current" "$backup/systemd-user/"
        fi
      done

      printf '%s\n' "$backup" > "$state/initial-backup-path"
      touch "$state/initial-backup-complete"
    fi

    # ----------------------------------------------------------
    # Upstream materialization
    # ----------------------------------------------------------

    export RYOKU_CONFIG_BASE="$base"

    ${ryoku.cli}/bin/ryoku materialize
    ${ryoku.cli}/bin/ryoku migrate-shell-config

    niri_gpu="$config_home/niri/gpu.kdl"

    if [ -f "$niri_gpu" ]; then
      tmp="$niri_gpu.ryoku-nix.$$"
      in_ryoku_nvidia_block=0

      : > "$tmp"

      while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = "// BEGIN RYOKU NIXOS NVIDIA NIRI WORKAROUNDS" ]; then
          in_ryoku_nvidia_block=1
          continue
        fi

        if [ "$line" = "// END RYOKU NIXOS NVIDIA NIRI WORKAROUNDS" ]; then
          in_ryoku_nvidia_block=0
          continue
        fi

        if [ "$in_ryoku_nvidia_block" -eq 0 ]; then
          printf '%s\n' "$line" >> "$tmp"
        fi
      done < "$niri_gpu"

      nvidia_render=0
      other_render=0

      for driver_link in /sys/class/drm/renderD*/device/driver; do
        [ -e "$driver_link" ] || continue

        driver="$(basename "$(readlink -f "$driver_link")")"

        if [ "$driver" = "nvidia" ]; then
          nvidia_render=$((nvidia_render + 1))
        else
          other_render=$((other_render + 1))
        fi
      done

      if [ "$nvidia_render" -gt 0 ] && [ "$other_render" -eq 0 ]; then
        cat >> "$tmp" <<'EOF'

// BEGIN RYOKU NIXOS NVIDIA NIRI WORKAROUNDS
debug {
    disable-cursor-plane
    emulate-zero-presentation-time
}
// END RYOKU NIXOS NVIDIA NIRI WORKAROUNDS
EOF
      fi

      # The first-login seed is the read-only store copy (0444); on the
      # session's tty a plain mv would prompt and hang the login.
      chmod --reference="$niri_gpu" "$tmp"
      mv -f -- "$tmp" "$niri_gpu"
    fi

    # config.kdl is niri's immutable Ryoku entrypoint and autostart.kdl is
    # the session bootstrap it includes. They track the shipped generation,
    # unlike the machine-owned monitor/GPU/keyboard/user seeds.
    #
    # Restore them on every materialization: losing either leaves a currently
    # running niri session alive only until its next restart.
    install -Dm0644 "$base/niri/config.kdl" \
      "$config_home/niri/config.kdl"
    install -Dm0644 "$base/niri/autostart.kdl" \
      "$config_home/niri/autostart.kdl"

    # Provider-generated effective config must be re-authored from desktop.json
    # on every generation switch. A provider update can change how the same
    # persisted settings are rendered; merely replacing the provider binary
    # would otherwise leave its old generated output in force until the user
    # happened to save a setting again.
    #
    # Generate both provider trees, not only the compositor running right now.
    # Ryoku preserves each provider's settings while switched away, so this also
    # guarantees that a later compositor switch starts from the current
    # generation rather than stale settings.lua/rebinds.lua or settings.kdl.
    ${ryoku.wmHyprland}/bin/ryoku-wm-hyprland apply \
      "$config_home/ryoku/desktop.json" >/dev/null

    ${ryoku.wmNiri}/bin/ryoku-wm-niri apply \
      "$config_home/ryoku/desktop.json" >/dev/null

    ${ryoku.wmMango}/bin/ryoku-wm-mango apply \
      "$config_home/ryoku/desktop.json" >/dev/null

    # Keep persisted Quick Settings state in step with Ryostage.
    #
    # Older NixOS installs may still carry the retired `depth` and
    # `parallax` modules because their shell.json survives generation
    # switches. Fold those entries into the unified `stage` module while
    # preserving the rest of the user's rail and its ordering.
    shell_store="$config_home/ryoku/shell.json"

    if [ -f "$shell_store" ]; then
      modules="$(
        jq -c \
          '.frameBars.menus["quick-settings"].modules // null' \
          "$shell_store" \
          2>/dev/null || true
      )"

      if [ -n "$modules" ] && [ "$modules" != "null" ]; then
        migrated="$(
          jq -c '
            if type != "array" then
              .
            elif any(.[]; . == "stage" or . == "depth" or . == "parallax") then
              reduce .[] as $module (
                { modules: [], stageAdded: false };

                if
                  $module == "stage"
                  or $module == "depth"
                  or $module == "parallax"
                then
                  if .stageAdded then
                    .
                  else
                    .modules += ["stage"] |
                    .stageAdded = true
                  end
                else
                  .modules += [$module]
                end
              ) |
              .modules
            elif index("home") then
              . + ["stage"]
            else
              .
            end
          ' <<< "$modules"
        )"

        if [ "$migrated" != "$modules" ]; then
          tmp="$shell_store.ryoku-nix-tmp"

          jq \
            --argjson modules "$migrated" \
            '.frameBars.menus["quick-settings"].modules = $modules' \
            "$shell_store" > "$tmp"

          chmod --reference="$shell_store" "$tmp"
          mv -f -- "$tmp" "$shell_store"
        fi
      fi
    fi

    # Seeds copied out of the Nix store need to remain writable.
    for file in \
      hypr/monitors.lua \
      hypr/gpu.lua \
      hypr/keyboard.lua \
      hypr/user.lua \
      niri/monitors.kdl \
      niri/gpu.kdl \
      niri/keyboard.kdl \
      niri/monitors_user.kdl \
      niri/user.kdl \
      niri/settings.kdl \
      niri/rebinds.kdl \
      mango/monitors.conf \
      mango/gpu.conf \
      mango/keyboard.conf \
      mango/monitors_user.conf \
      mango/user.conf \
      mango/settings.conf \
      mango/rebinds.conf \
      fastfetch/config.jsonc \
      kitty/current-theme.conf
    do
      path="$config_home/$file"

      # Home Manager commonly manages config as symlinks into /nix/store.
      # Only normal materialized files should have their mode changed.
      if [ -f "$path" ] && [ ! -L "$path" ]; then
        chmod u+w "$path"
      fi
    done

    # ----------------------------------------------------------
    # QML modules
    #
    # Upstream env.lua expects ~/.local/lib/qt6/qml for a
    # non-/usr development deployment.
    # ----------------------------------------------------------

    user_qml="$HOME/.local/lib/qt6/qml/Ryoku"

    mkdir -p "$user_qml"

    for module in Ui PluginKit FrameBars Blobs Wm; do
      module_path="$user_qml/$module"

      # Older NixOS generations copied these modules out of the Nix store with
      # their immutable 0555 directory modes intact. The first deployment
      # therefore worked, but a later materialization could not rm -rf the old
      # tree before replacing it. Make only legacy real directories writable;
      # current generations use symlinks and must never chmod the store target.
      if [ -d "$module_path" ] && [ ! -L "$module_path" ]; then
        find "$module_path" -type d -exec chmod u+w {} +
      fi

      rm -rf -- "''${module_path:?}"

      ln -s \
        "$qml/Ryoku/$module" \
        "$module_path"
    done

    # Hyprland's bundled plugins are immutable generation-owned packages.
    # Older Ryoku-on-NixOS revisions exposed them through ~/.local symlinks;
    # Hub now receives the store package directory directly instead.
    #
    # Remove only those old symlinks. A real user-created plugin file is left
    # alone, although bundled plugin IDs are ignored by Hub while Nix owns them.
    plugin_dir="$HOME/.local/lib/hyprland/plugins"

    if [ -d "$plugin_dir" ]; then
      for plugin in \
        dynamic-cursors \
        hyprbars \
        hyprfocus \
        hyprglass \
        imgborders \
        keysounds
      do
        if [ -L "$plugin_dir/$plugin.so" ]; then
          rm -f -- "$plugin_dir/$plugin.so"
        fi
      done
    fi

    # ----------------------------------------------------------
    # NixOS owns Ryoku's systemd user units declaratively.
    #
    # Remove legacy units left by an older materialization or an
    # existing Arch Ryoku deployment. User-local units otherwise
    # override the NixOS-managed definitions.
    # ----------------------------------------------------------

    # Preserve the Palette Bridge's user-selected enablement while replacing
    # any old Arch/self-installed unit definition with the immutable NixOS one.
    palette_bridge_enabled=0

    if systemctl --user is-enabled --quiet ryoku-palette-bridge.service 2>/dev/null; then
      palette_bridge_enabled=1
    fi

    rm -f -- \
      "$user_units/ryoku-session.target" \
      "$user_units/hyprland-session.target" \
      "$user_units/ryoku-shell.service" \
      "$user_units/ryogami.service" \
      "$user_units/ryoku-session.target.wants/ryoku-materialize.service" \
      "$user_units/ryoku-session.target.wants/ryoku-shell.service" \
      "$user_units/ryoku-session.target.wants/ryogami.service" \
      "$user_units/ryoku-session.target.wants/ryoku-bluetooth-reset.service" \
      "$user_units/ryoku-session.target.wants/ryoku-clamshell.service" \
      "$user_units/ryoku-session.target.wants/ryoku-idle.service" \
      "$user_units/default.target.wants/ryoku-rashin.service" \
      "$user_units/ryoku-rashin.service" \
      "$user_units/ryoku-ai-usage.service" \
      "$user_units/ryoku-ai-usage.timer" \
      "$user_units/ryoku-palette-bridge.service"

    systemctl --user daemon-reload 2>/dev/null || true

    if [ "$palette_bridge_enabled" -eq 1 ]; then
      systemctl --user reenable ryoku-palette-bridge.service         >/dev/null 2>&1 || true
    fi

    # ----------------------------------------------------------
    # Seed visible assets without replacing user files
    # ----------------------------------------------------------

    data_home="''${XDG_DATA_HOME:-$HOME/.local/share}"

    mkdir -p \
      "$HOME/Pictures/Wallpapers" \
      "$HOME/Pictures/ryodecors" \
      "$data_home/ryoku/assets/brand"

    if [ -d "${ryoku.desktopData}/share/ryoku/wallpapers" ]; then
      cp -n \
        "${ryoku.desktopData}/share/ryoku/wallpapers/"* \
        "$HOME/Pictures/Wallpapers/" \
        2>/dev/null || true
    fi

    if [ -d "${ryoku.desktopData}/share/ryoku/ryodecors" ]; then
      cp -n \
        "${ryoku.desktopData}/share/ryoku/ryodecors/"* \
        "$HOME/Pictures/ryodecors/" \
        2>/dev/null || true
    fi

    if [ -d "${ryoku.desktopData}/share/ryoku/brand" ]; then
      cp -n \
        "${ryoku.desktopData}/share/ryoku/brand/"* \
        "$data_home/ryoku/assets/brand/" \
        2>/dev/null || true
    fi

    # User-space equivalents for integrations normally installed under /usr.
    ryoku_data="$data_home/ryoku"

    mkdir -p \
      "$data_home/nautilus-python/extensions" \
      "$ryoku_data/spicetify"

    ln -sfn \
      "${ryoku.desktopData}/share/ryoku/nautilus/ryoku-stash-menu.py" \
      "$data_home/nautilus-python/extensions/ryoku-stash-menu.py"

    if [ ! -e "$ryoku_data/browser" ] || [ -L "$ryoku_data/browser" ]; then
      ln -sfnT \
        "${ryoku.desktopData}/share/ryoku/browser" \
        "$ryoku_data/browser"
    fi

    ln -sfn \
      "${ryoku.desktopData}/share/ryoku/spicetify/ryoku-canvas.js" \
      "$ryoku_data/spicetify/ryoku-canvas.js"

    printf '\n'
    printf 'Ryoku desktop materialized successfully.\n'

    if [ -f "$state/initial-backup-path" ]; then
      printf 'Original config backup: %s\n' \
        "$(cat "$state/initial-backup-path")"
    fi

    printf '\nLog out and start a Ryoku session (Hyprland, niri, or MangoWM).\n'
  '';
}
