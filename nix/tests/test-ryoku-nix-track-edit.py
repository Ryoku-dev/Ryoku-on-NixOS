#!/usr/bin/env python3

from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest


EDITOR = (
    Path(__file__).resolve().parents[1]
    / "scripts"
    / "ryoku-nix-track-edit.py"
)


def edit(text, source, slim=False):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "flake.nix"
        path.write_text(text)

        env = os.environ.copy()
        env.pop("RYOKU_NIX_HYPERION_NIRI_ONLY", None)
        if slim:
            env["RYOKU_NIX_HYPERION_NIRI_ONLY"] = "1"

        proc = subprocess.run(
            [
                sys.executable,
                str(EDITOR),
                str(path),
                source,
            ],
            text=True,
            capture_output=True,
            env=env,
        )

        if proc.returncode != 0:
            raise AssertionError(proc.stderr)

        return path.read_text()


class TrackEditorTests(unittest.TestCase):
    def test_block_input(self):
        text = """{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    ryoku = {
      url = "github:Ryoku-dev/Ryoku-on-NixOS/main";
    };
  };

  outputs = { self, nixpkgs, ryoku, ... }: {};
}
"""

        got = edit(
            text,
            "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
        )

        self.assertIn(
            'url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";',
            got,
        )

        self.assertIn(
            'nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";',
            got,
        )

    def test_dotted_input(self):
        text = """{
  inputs.ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/main";

  outputs = { self, ryoku, ... }: {};
}
"""

        got = edit(
            text,
            "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
        )

        self.assertIn(
            'inputs.ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";',
            got,
        )


    def test_hyperion_enables_preview_and_restores_cleanly(self):
        original = """{
  inputs.ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";
  outputs = { self, ryoku, ... }: {
    programs.ryoku.enable = true;
  };
}
"""
        hyperion = edit(
            original,
            "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos",
        )
        self.assertIn("programs.ryoku.hyperionPackages.enable = true;", hyperion)
        self.assertEqual(
            edit(hyperion, "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev"),
            original,
        )

    def test_hyperion_slim_keeps_niri_and_removes_legacy_input(self):
        original = """{
  inputs.ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";
  inputs.ryotunesNix.url = "github:Ryoku-dev/RyotunesNix/f706915c68a0b914756db877e0a2aeb0daef41cd";
  outputs = { self, ryoku, ... }: {
    programs.ryoku.enable = true;
  };
}
"""
        hyperion = edit(
            original,
            "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos",
            slim=True,
        )
        self.assertIn("programs.ryoku.hyperionNiriOnly.enable = true;", hyperion)
        self.assertNotIn("inputs.ryotunesNix.url", hyperion)
        self.assertEqual(
            edit(hyperion, "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos"),
            hyperion,
        )
        reverted = edit(hyperion, "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev")
        self.assertNotIn("hyperionNiriOnly", reverted)
        self.assertNotIn("hyperionPackages.enable", reverted)

    def test_hyperion_rejects_external_option(self):
        original = """{
  inputs.ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";
  outputs = { self, ryoku, ... }: {
    programs.ryoku.enable = true;
    programs.ryoku.hyperionPackages.enable = false;
  };
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "flake.nix"
            path.write_text(original)
            proc = subprocess.run(
                [
                    sys.executable,
                    str(EDITOR),
                    str(path),
                    "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos",
                ],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(path.read_text(), original)


ISO_FLAKE = """{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";
  };
  outputs = { nixpkgs, ryoku, ... }: {
    nixosConfigurations.ryoku = nixpkgs.lib.nixosSystem {
      modules = [ ryoku.nixosModules.default ./ryoku.nix ./configuration.nix ];
    };
  };
}
"""

ISO_MODULE = (
    Path(__file__).resolve().parents[1] / "iso-configs" / "ryoku.nix"
).read_text()


def edit_pair(flake, module, source, slim=False):
    with tempfile.TemporaryDirectory() as tmp:
        flake_path = Path(tmp) / "flake.nix"
        module_path = Path(tmp) / "ryoku.nix"
        flake_path.write_text(flake)
        module_path.write_text(module)
        env = os.environ.copy()
        env.pop("RYOKU_NIX_HYPERION_NIRI_ONLY", None)
        if slim:
            env["RYOKU_NIX_HYPERION_NIRI_ONLY"] = "1"
        proc = subprocess.run(
            [sys.executable, str(EDITOR), str(flake_path), source, str(module_path)],
            text=True, capture_output=True, env=env,
        )
        return proc, flake_path.read_text(), module_path.read_text()


class InstallerLayoutTests(unittest.TestCase):
    HYPERION = "github:Ryoku-dev/Ryoku-on-NixOS/feature/hyperion-v2-nixos"
    UNSTABLE = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev"

    def test_enter_and_leave_round_trip(self):
        proc, flake, module = edit_pair(ISO_FLAKE, ISO_MODULE, self.HYPERION)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(f'ryoku.url = "{self.HYPERION}";', flake)
        self.assertIn("    hyperionPackages.enable = true; # ryoku-v2-switcher\n", module)
        self.assertNotIn("hyperionPackages", flake)

        proc, flake, module = edit_pair(flake, module, self.UNSTABLE)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(flake, ISO_FLAKE)
        self.assertEqual(module, ISO_MODULE)

    def test_slim_and_idempotence(self):
        proc, flake, module = edit_pair(ISO_FLAKE, ISO_MODULE, self.HYPERION, slim=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("    hyperionNiriOnly.enable = true; # ryoku-v2-slim\n", module)
        again = edit_pair(flake, module, self.HYPERION, slim=True)
        self.assertEqual(again[1:], (flake, module))
        proc, flake, module = edit_pair(flake, module, self.UNSTABLE)
        self.assertEqual(module, ISO_MODULE)

    def test_manual_module_option_is_left_alone(self):
        manual = ISO_MODULE.replace(
            "    enable = true;\n", "    enable = true;\n    hyperionPackages.enable = false;\n"
        )
        proc, flake, module = edit_pair(ISO_FLAKE, manual, self.HYPERION)
        self.assertNotEqual(proc.returncode, 0)

    def test_flake_declaration_wins_over_module(self):
        flake = ISO_FLAKE.replace(
            "./configuration.nix ];",
            "./configuration.nix { programs.ryoku.enable = true; } ];",
        )
        flake = flake.replace("./configuration.nix { programs", "./configuration.nix\n        {\n          programs").replace(
            "true; } ];", "true;\n        }\n      ];")
        proc, new_flake, module = edit_pair(flake, ISO_MODULE, self.HYPERION)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("programs.ryoku.hyperionPackages.enable = true; # ryoku-v2-switcher", new_flake)
        self.assertEqual(module, ISO_MODULE)


if __name__ == "__main__":
    unittest.main(verbosity=2)
