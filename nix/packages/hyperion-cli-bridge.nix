{ pkgs, upstreamCli, nixUpdate }:

pkgs.writeShellScriptBin "ryoku" ''
  if [ "''${1:-}" = update ]; then
    shift
    if [ "$#" -gt 0 ]; then
      printf 'ryoku update on NixOS takes no options. Run ryoku-nix-update update.\n' >&2
      exit 2
    fi
    exec ${nixUpdate}/bin/ryoku-nix-update update
  fi

  exec ${upstreamCli}/bin/ryoku "$@"
''
