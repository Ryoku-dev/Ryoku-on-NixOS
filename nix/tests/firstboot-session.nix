# First-boot session contract of the system the installer builds.
#
# Evaluation only: every fact below is read from the evaluated NixOS
# configuration, so the check needs no desktop build and no VM.
{ pkgs, config }:
let
  inherit (pkgs) lib;

  dm = config.services.displayManager;

  # SDDM runs a Wayland session's Exec through its wayland-session script,
  # whose PATH comes from /etc/profile. NixOS installs session packages only
  # into the session directory, never into /run/current-system/sw/bin, so a
  # bare command name in a Ryoku entry is "command not found" at login.
  ryokuSessions = lib.filter (p: lib.hasPrefix "ryoku-" (p.name or "")) dm.sessionPackages;

  execLines = pkg:
    lib.filter (l: lib.hasPrefix "Exec=" l)
      (lib.splitString "\n" (pkg.buildCommand or ""));

  execProblems = pkg:
    let lines = execLines pkg; in
    lib.optional (lines == [ ]) "${pkg.name}: no Exec= line found in its session entry"
    ++ map (l: "${pkg.name}: ${l} is not an absolute path; the greeter cannot find it on PATH")
      (lib.filter
        (l: !(lib.hasPrefix "Exec=$out/" l || lib.hasPrefix "Exec=/" l))
        lines);

  sessionNames = lib.concatMap (p: p.providedSessions or [ ]) ryokuSessions;

  problems =
    lib.concatMap execProblems ryokuSessions
    ++ lib.optional
      (sessionNames != [ "ryoku-hyprland" "ryoku-niri" "ryoku-mango" ])
      "Ryoku session entries changed: ${builtins.toJSON sessionNames}"
    ++ lib.optional (!(builtins.elem dm.defaultSession sessionNames))
      "default session ${builtins.toJSON dm.defaultSession} is not a Ryoku session";
in
assert lib.assertMsg (problems == [ ])
  ("first-boot session contract:\n" + lib.concatStringsSep "\n" problems);
pkgs.writeText "ryoku-firstboot-session-check"
  (lib.concatMapStrings (n: "ok ${n}\n") sessionNames)
