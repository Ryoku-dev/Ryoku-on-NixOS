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
      url = "github:aethctl/Ryoku-on-NixOS/main";
    };
  };

  outputs = { self, nixpkgs, ryoku, ... }: {};
}
"""

        got = edit(
            text,
            "github:aethctl/Ryoku-on-NixOS/unstable-dev",
        )

        self.assertIn(
            'url = "github:aethctl/Ryoku-on-NixOS/unstable-dev";',
            got,
        )

        self.assertIn(
            'nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";',
            got,
        )

    def test_dotted_input(self):
        text = """{
  inputs.ryoku.url = "github:aethctl/Ryoku-on-NixOS/main";

  outputs = { self, ryoku, ... }: {};
}
"""

        got = edit(
            text,
            "github:aethctl/Ryoku-on-NixOS/unstable-dev",
        )

        self.assertIn(
            'inputs.ryoku.url = "github:aethctl/Ryoku-on-NixOS/unstable-dev";',
            got,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
