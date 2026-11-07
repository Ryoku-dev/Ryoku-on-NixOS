# `only` restricts the matrix to the named runs, e.g. [ "bare (x11)" ],
# when investigating a single case with nix eval.
{ pkgs, module, only ? null }:
let
  inherit (pkgs) lib;

  # Every case shares one package set; instantiating Nixpkgs per case would
  # make the matrix several times slower. Ryoku's unfree predicate therefore
  # becomes allowUnfree, which display-manager selection does not depend on.
  hostPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };

  # A minimally bootable synthetic NixOS host.
  hostBaseline = {
    system.stateVersion = "26.05";

    nixpkgs.pkgs = hostPkgs;
    nixpkgs.config = lib.mkForce { };

    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };

    boot.loader.grub = {
      enable = true;
      devices = [ "/dev/vda" ];
    };
  };

  evaluate = extra: import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = pkgs.stdenv.hostPlatform.system;

    modules = [
      module
      hostBaseline
      { programs.ryoku.enable = true; }
      extra
    ];
  };

  bare = evaluate { };

  # Only exercise display managers this nixpkgs actually provides.
  hasOption = path: lib.hasAttrByPath path bare.options;

  # Every case runs without and with Xserver: most existing NixOS installs
  # Ryoku is added to have services.xserver.enable = true.
  #
  #   expect   option values after evaluation (see `observed`).
  #   rejects  NixOS itself must refuse the configuration. A string is a
  #            substring of a failed NixOS assertion; { option = [ ... ]; }
  #            names an option whose definitions must conflict.
  #   x11Only  the configuration only exists with Xserver.
  #
  # Any value may be split per host as { wayland = ...; x11 = ...; }.
  #
  # With no login manager chosen, a No Desktop install (no Xserver) gets
  # Ryoku's SDDM with its Wayland backend. An Xserver host keeps NixOS' own
  # default, LightDM.
  unchosen = {
    sddm = { wayland = true; x11 = false; };
    lightdm = { wayland = false; x11 = true; };
    theme = { wayland = "ryoku"; x11 = ""; };
    sddmWayland = { wayland = true; x11 = false; };
  };

  # SDDM chosen by the host: Ryoku themes it, and supplies the Wayland
  # backend only when there is no Xserver to run it on.
  sddmChosen = {
    sddm = true;
    lightdm = false;
    theme = "ryoku";
    sddmWayland = { wayland = true; x11 = false; };
  };

  cases = [
    { name = "bare"; config = { }; expect = unchosen; }

    { name = "sddm-enabled";
      config.services.displayManager.sddm.enable = true;
      expect = sddmChosen; }

    # Turning SDDM off leaves NixOS' own choice: LightDM on X11, none otherwise.
    { name = "sddm-disabled";
      config.services.displayManager.sddm.enable = false;
      expect = { sddm = false; lightdm = { wayland = false; x11 = true; }; }; }

    { name = "sddm-force-disabled";
      config.services.displayManager.sddm.enable = lib.mkForce false;
      expect = { sddm = false; lightdm = { wayland = false; x11 = true; }; }; }

    { name = "sddm-custom-theme";
      config.services.displayManager.sddm.theme = "custom";
      expect = unchosen // { theme = "custom"; }; }

    { name = "sddm-enabled-custom-theme";
      config.services.displayManager.sddm = {
        enable = true;
        theme = "custom";
      };
      expect = sddmChosen // { theme = "custom"; }; }

    { name = "sddm-wayland-on";
      config.services.displayManager.sddm.wayland.enable = true;
      expect = unchosen // { sddmWayland = true; }; }

    # Without Xserver or the Wayland backend SDDM cannot start, and NixOS'
    # own assertion must still say so.
    { name = "sddm-wayland-off";
      config.services.displayManager.sddm.wayland.enable = false;
      expect = unchosen // { sddmWayland = false; };
      rejects.wayland = "SDDM requires either services.xserver.enable or services.displayManager.sddm.wayland.enable";
      rejects.x11 = null; }

    { name = "lightdm";
      config.services.xserver.displayManager.lightdm.enable = true;
      expect = { sddm = false; lightdm = true; };
      rejects.wayland = "LightDM requires services.xserver.enable to be true";
      rejects.x11 = null; }

    { name = "gdm";
      config.services.displayManager.gdm.enable = true;
      expect = { sddm = false; lightdm = false; }; }

    { name = "greetd";
      config.services.greetd = {
        enable = true;
        settings.default_session.command = "agreety --cmd bash";
      };
      expect = { sddm = false; lightdm = false; }; }

    # Explicitly enabling two display managers is the user's conflict to
    # resolve; Ryoku must not hide NixOS' error by dropping one of them.
    { name = "sddm-and-gdm";
      config.services.displayManager = {
        sddm.enable = true;
        gdm.enable = true;
      };
      expect = { sddm = true; };
      rejects.option = [ "services" "displayManager" "generic" "execCmd" ]; }

    # Existing desktop environments.
    #
    # Plasma and nixpkgs' Niri module both default defaultSession, so a
    # Plasma host only evaluates once the installer has picked Ryoku's
    # compositor. Manual integrations must still set defaultSession.
    { name = "plasma6";
      config = {
        services.desktopManager.plasma6.enable = true;
        programs.ryoku.defaultCompositor = "hyprland";
      };
      # Plasma's own SDDM defaults stay, but Ryoku's theme wins when active.
      expect = unchosen // {
        sddmWayland = true;
        theme = { wayland = "ryoku"; x11 = "breeze"; };
        defaultSession = "ryoku-hyprland";
      }; }

    { name = "plasma6-sddm";
      config = {
        services.desktopManager.plasma6.enable = true;
        services.displayManager.sddm.enable = true;
        programs.ryoku.defaultCompositor = "hyprland";
      };
      expect = sddmChosen // {
        sddmWayland = true;
        defaultSession = "ryoku-hyprland";
      }; }

    { name = "gnome";
      config = {
        services.desktopManager.gnome.enable = true;
        services.displayManager.gdm.enable = true;
      };
      expect = { sddm = false; lightdm = false; }; }

    { name = "xfce";
      x11Only = true;
      config.services.xserver.desktopManager.xfce.enable = true;
      expect = unchosen; }
  ]
  ++ lib.optional (hasOption [ "services" "displayManager" "lemurs" "enable" ]) {
    name = "lemurs";
    config.services.displayManager.lemurs.enable = true;
    expect = { sddm = false; lightdm = false; };
  }
  ++ lib.optional (hasOption [ "services" "displayManager" "plasma-login-manager" "enable" ]) {
    name = "plasma-login-manager";
    config.services.displayManager.plasma-login-manager.enable = true;
    expect = { sddm = false; lightdm = false; };
  }
  ++ lib.optional (hasOption [ "services" "displayManager" "ly" "enable" ]) {
    name = "ly";
    config.services.displayManager.ly.enable = true;
    expect = { sddm = false; lightdm = false; };
  }
  ++ lib.optional (hasOption [ "services" "displayManager" "cosmic-greeter" "enable" ]) {
    name = "cosmic-greeter";
    config.services.displayManager.cosmic-greeter.enable = true;
    expect = { sddm = false; lightdm = false; };
  };

  label = run: "${run.case.name} (${if run.x11 then "x11" else "wayland"})";

  runs = lib.filter (run: only == null || builtins.elem (label run) only)
    (lib.concatMap
      (case: map (x11: { inherit case x11; })
        (lib.optional (!(case.x11Only or false)) false ++ [ true ]))
      cases);

  pick = x11: value:
    if builtins.isAttrs value && value ? wayland && value ? x11
    then (if x11 then value.x11 else value.wayland)
    else value;

  observed = config: {
    sddm = config.services.displayManager.sddm.enable;
    lightdm = config.services.xserver.displayManager.lightdm.enable;
    theme = config.services.displayManager.sddm.theme;
    sddmWayland = config.services.displayManager.sddm.wayland.enable;
    defaultSession = config.services.displayManager.defaultSession;
  };

  # The problems found in one run; [ ] means it behaved.
  #
  # Each system is evaluated down to system.build.toplevel's drvPath, which
  # runs every NixOS assertion and option merge without building anything.
  # builtins.tryEval only catches throw and assert. An infinite recursion
  # aborts the whole check, naming the case in its trace, so it can never
  # pass as an expected rejection.
  problems = run:
    let
      name = label run;
      config = (evaluate {
        imports = [ run.case.config ];
        services.xserver.enable = run.x11;
      }).config;

      expect = lib.mapAttrs (_: pick run.x11) run.case.expect;
      actual = lib.getAttrs (builtins.attrNames expect) (observed config);
      rejects = pick run.x11 (run.case.rejects or null);

      failed = map (a: a.message) (lib.filter (a: !a.assertion) config.assertions);
      toplevel = (builtins.tryEval (builtins.unsafeDiscardStringContext
        config.system.build.toplevel.drvPath)).success;

      found =
        lib.optional (actual != expect)
          "${name}: expected ${builtins.toJSON expect}, got ${builtins.toJSON actual}"
        ++ (if rejects == null then
          lib.optional (failed != [ ])
            "${name}: unexpected NixOS assertions: ${builtins.toJSON failed}"
          ++ lib.optional (failed == [ ] && !toplevel)
            "${name}: system.build.toplevel does not evaluate"
        else if builtins.isString rejects then
          lib.optional (!lib.any (lib.hasInfix rejects) failed)
            "${name}: expected NixOS to fail with \"${rejects}\", got ${builtins.toJSON failed}"
          ++ lib.optional toplevel
            "${name}: system.build.toplevel evaluated despite that"
        else
          lib.optional (builtins.tryEval (lib.getAttrFromPath rejects.option config)).success
            "${name}: expected conflicting definitions of ${lib.showOption rejects.option}"
          ++ lib.optional toplevel
            "${name}: system.build.toplevel evaluated despite that");
    in
    builtins.addErrorContext "while evaluating display-manager case ${name}"
      (builtins.deepSeq found found);

  matrixProblems = lib.concatMap problems runs;

  niriDefault = (evaluate {
    programs.ryoku.defaultCompositor = "niri";
  }).config;

  userDefault = (evaluate {
    programs.ryoku.defaultCompositor = "hyprland";
    services.displayManager.defaultSession = "niri";
  }).config;

  firefoxBrowser = (evaluate {
    programs.ryoku.browser = "firefox";
  }).config;
in

# Ryoku itself must not turn a No Desktop host into an Xserver one; the
# matrix below sets services.xserver.enable explicitly either way.
assert !bare.config.services.xserver.enable;

assert lib.assertMsg (matrixProblems == [ ])
  ("display-manager matrix:\n" + lib.concatStringsSep "\n" matrixProblems);

# The installer-selected compositor beats provider defaults, while an explicit
# host choice still beats the installer preference.
assert niriDefault.services.displayManager.defaultSession == "ryoku-niri";
assert userDefault.services.displayManager.defaultSession == "niri";

# Browser selection is declarative and reaches both PATH and the shell fallback.
assert builtins.elem pkgs.firefox firefoxBrowser.environment.systemPackages;
assert firefoxBrowser.environment.sessionVariables.RYOKU_DEFAULT_BROWSER == "firefox";

# Everything above is decided during evaluation, so the check depends on no
# system closure.
pkgs.writeText "ryoku-display-manager-check"
  (lib.concatMapStrings (run: "ok ${label run}\n") runs)
