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


if __name__ == "__main__":
    unittest.main(verbosity=2)
