#!/usr/bin/env python3
"""Evaluate the RyoStore Shima install source the way RyoStore consumes it.

RyoStore installs Shima with `nix build path:$RYOKU_SHIMA_FLAKE#default`. That
is a pure flake evaluation: every file the package expression touches has to be
inside the generated source. Regressions of this class shipped twice as missing
files (c073298a, 6b3930e8) and once as a repository-relative path that escapes
the generated flake (c84327f7).

The check evaluates the generated flake's own `outputs` in restricted mode,
with only the install source, the pinned Nixpkgs and the pinned iNiR source on
the search path, so any access outside them fails exactly like the flake does.
It uses a throwaway local store, so it runs inside the Nix build sandbox.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--install-source", required=True, type=Path)
parser.add_argument("--nixpkgs", required=True, type=Path)
parser.add_argument("--inir", required=True, type=Path)
parser.add_argument("--expected-drv", help="drvPath of the flake's own ryoku-shima package")
args = parser.parse_args()

EXPR = """
let
  flake = import <ryoku-shima-source/flake.nix>;
  outputs = flake.outputs {
    self = { outPath = <ryoku-shima-source>; };
    nixpkgs = {
      outPath = <ryoku-shima-nixpkgs>;
      legacyPackages.x86_64-linux = import <ryoku-shima-nixpkgs> { system = "x86_64-linux"; };
    };
    inirSrc = { outPath = <ryoku-shima-inir>; };
  };
in outputs.packages.x86_64-linux.default.drvPath
"""

with tempfile.TemporaryDirectory(prefix="subshell-store-source-") as tmp:
    root = Path(tmp)
    env = {
        "PATH": os.environ["PATH"],
        "HOME": str(root / "home"),
        "NIX_STATE_DIR": str(root / "state"),
        "NIX_LOG_DIR": str(root / "log"),
        "NIX_CONF_DIR": str(root / "conf"),
        "XDG_CACHE_HOME": str(root / "cache"),
    }
    (root / "conf").mkdir()
    (root / "conf/nix.conf").write_text("")
    result = subprocess.run(
        [
            "nix-instantiate", "--eval", "--strict", "--json",
            "--store", str(root / "store"),
            "--option", "restrict-eval", "true",
            "--option", "build-users-group", "",
            "--option", "substituters", "",
            "-I", f"ryoku-shima-source={args.install_source}",
            "-I", f"ryoku-shima-nixpkgs={args.nixpkgs}",
            "-I", f"ryoku-shima-inir={args.inir}",
            "--expr", EXPR,
        ],
        env=env, capture_output=True, text=True, timeout=600,
    )

if result.returncode != 0:
    raise SystemExit(
        "RyoStore Shima install source does not evaluate on its own; every file "
        "ryoku-shima.nix uses must be shipped inside it.\n" + result.stderr[-4000:]
    )

drv = result.stdout.strip().strip('"')
assert drv.startswith("/nix/store/") and drv.endswith(".drv"), drv
if args.expected_drv:
    assert drv == args.expected_drv, (
        "RyoStore would build a different Shima than the flake ships:\n"
        f"  install source: {drv}\n  flake package:  {args.expected_drv}"
    )
print(f"RyoStore Shima install source evaluates on its own: {drv}")
