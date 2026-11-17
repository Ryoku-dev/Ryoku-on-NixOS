# The NixOS system bridge must be the only owner of its privileged commands.
#
# Everything here inspects built package outputs and the evaluated module:
# the resolved PATH entries, the generated polkit rules and the compiled
# shell/CLI binaries. No assertion is a pattern over repository sources.
{
  pkgs,
  bridge,
  helpers,
  bundle,
  shell,
  cli,
  # config.environment.systemPackages of an evaluated Ryoku host.
  systemPackages,
  # config.security.polkit.extraConfig of the same host.
  polkitRules,
}:

let
  lib = pkgs.lib;

  # Mirror NixOS' system-path: same package order and the same
  # ignoreCollisions semantics, restricted to Ryoku's own packages so the
  # check does not need to realise the whole desktop closure.
  ryokuSystemPath = pkgs.buildEnv {
    name = "ryoku-system-path-model";
    paths = builtins.filter
      (pkg: lib.hasPrefix "ryoku" (lib.getName pkg))
      systemPackages;
    pathsToLink = [ "/bin" ];
    ignoreCollisions = true;
  };

  rules = pkgs.writeText "ryoku-polkit-rules.js" polkitRules;
in
pkgs.runCommand "ryoku-bridge-command-ownership-check"
  {
    nativeBuildInputs = [ pkgs.coreutils pkgs.gnugrep ];
  }
  ''
    fail() {
      printf 'bridge-command-ownership: %s\n' "$*" >&2
      exit 1
    }

    bridge_bin=${bridge}/bin

    for name in ${lib.escapeShellArgs bridge.passthru.commands}; do
      owner="$(readlink -f "$bridge_bin/$name")"
      [ -f "$owner" ] && [ -x "$owner" ] ||
        fail "$name is missing from the bridge package"

      # No duplicate implementation may ship beside the bridge.
      [ ! -e "${helpers}/bin/$name" ] ||
        fail "ryoku-helpers still ships $name"

      for view in ${bundle}/bin ${ryokuSystemPath}/bin; do
        [ -e "$view/$name" ] || fail "$name is not on PATH via $view"
        resolved="$(readlink -f "$view/$name")"
        [ "$resolved" = "$owner" ] ||
          fail "$view/$name resolves to $resolved, not the bridge ($owner)"
      done

      # The bridge elevates with pkexec "$(readlink -f "$0")", so the program
      # polkit sees is the canonical path checked above. It must be granted.
      grep -Fq '"'"$owner"'"' ${rules} ||
        fail "no polkit grant for the resolved program $owner"
      grep -Fq 'readlink -f "$0"' "$owner" ||
        fail "$name no longer elevates through its canonical path"
    done

    # The shell daemon runs the DNS helper by absolute path.
    dns="$(readlink -f "$bridge_bin/ryoku-dns")"
    grep -aFq "$dns" ${shell}/bin/ryoku-shell ||
      fail "ryoku-shell does not reference the bridge ryoku-dns"
    ! grep -aFq '/usr/bin/ryoku-dns' ${shell}/bin/ryoku-shell ||
      fail "ryoku-shell still references /usr/bin/ryoku-dns"

    # ryoku-host dispatches `network wifi-backend` and hands pkexec an
    # absolute path so the polkit grant can match. (The `ryoku` binary links
    # the same package, but Go drops the unreferenced Network method.)
    wifi="$bridge_bin/ryoku-wifi-backend"
    grep -aFq "$wifi" ${cli}/bin/.ryoku-host-wrapped ||
      fail "ryoku-host does not call the bridge ryoku-wifi-backend"
    grep -Fq '"'"$wifi"'"' ${rules} ||
      fail "no polkit grant for the CLI's ryoku-wifi-backend path"

    touch "$out"
  ''
