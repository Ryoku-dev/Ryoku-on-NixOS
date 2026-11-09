#!/usr/bin/env python3

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


EDITOR = (
    Path(__file__).resolve().parents[1]
    / "scripts"
    / "ryoku-nix-track-edit.py"
)


def edit(text, source):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "flake.nix"
        path.write_text(text)

        proc = subprocess.run(
            [
                sys.executable,
                str(EDITOR),
                str(path),
                source,
            ],
            text=True,
            capture_output=True,
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
