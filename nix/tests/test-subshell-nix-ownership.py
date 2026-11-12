#!/usr/bin/env python3
"""On NixOS the packaged ryoku-shima is the only Shima runtime.

The Arch runtime arrives with upstream syncs: a pinned overlay plus the
ryoku-shima, ryoku-shima-install and ryoku-shima-wallpaper scripts that
download and run a mutable copy under $XDG_DATA_HOME. 785c5615 removed the
overlay from the desktop data. The scripts must not reach the system PATH
either, because:

- the daemon and RyoStore find the runtime with `exec.LookPath("ryoku-shima")`.
  An Arch launcher there makes RyoStore report Shima as installed and core when
  it is not installed;
- system-path keeps the first of two colliding commands, so with
  programs.ryoku.shima.enable an earlier Ryoku package would shadow the Nix
  runtime.

The system-path inputs are models of NixOS' system-path built from the
evaluated host's own package list (same order, same collision rule).
"""
import argparse
import os
from pathlib import Path
import unittest

parser = argparse.ArgumentParser()
parser.add_argument("--shima", required=True, type=Path, help="ryoku-shima package")
parser.add_argument("--system-path", required=True, type=Path,
                    help="system-path model of a host with programs.ryoku.shima.enable")
parser.add_argument("--system-path-without-shima", required=True, type=Path,
                    help="system-path model of a default Ryoku host")
parser.add_argument("--desktop-data", required=True, type=Path)
args = parser.parse_args()

SHIMA_COMMANDS = sorted(p.name for p in (args.shima / "bin").iterdir())
ARCH_ONLY_COMMANDS = ["ryoku-shima-install"]


class ShimaNixOwnershipTests(unittest.TestCase):
    def test_package_provides_the_launcher(self):
        self.assertIn("ryoku-shima", SHIMA_COMMANDS)

    def test_enabled_shima_commands_resolve_to_the_nix_runtime(self):
        owner = args.shima.resolve()
        for name in SHIMA_COMMANDS:
            with self.subTest(command=name):
                entry = args.system_path / "bin" / name
                self.assertTrue(entry.exists(), f"{name} is not on the system PATH")
                resolved = entry.resolve()
                self.assertTrue(resolved.is_relative_to(owner),
                                f"{name} resolves to {resolved}, not the Shima package {owner}")

    def test_default_host_has_no_shima_runtime_on_path(self):
        for name in SHIMA_COMMANDS + ARCH_ONLY_COMMANDS:
            with self.subTest(command=name):
                entry = args.system_path_without_shima / "bin" / name
                self.assertFalse(os.path.lexists(entry),
                                 f"{name} is on PATH without Shima: {entry.resolve()}")

    def test_arch_runtime_installer_is_not_shipped(self):
        for name in ARCH_ONLY_COMMANDS:
            with self.subTest(command=name):
                entry = args.system_path / "bin" / name
                self.assertFalse(os.path.lexists(entry),
                                 f"Arch-only {name} is on the NixOS PATH: {entry.resolve()}")

    def test_arch_overlay_is_not_in_desktop_data(self):
        leaked = [str(path) for path in args.desktop_data.rglob("shima-overlay")]
        self.assertEqual(leaked, [])


if __name__ == "__main__":
    unittest.main(argv=["test-subshell-nix-ownership"], verbosity=2)
