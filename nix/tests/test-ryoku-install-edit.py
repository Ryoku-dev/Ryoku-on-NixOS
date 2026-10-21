#!/usr/bin/env python3

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


def load_parser():
    default = (
        Path(__file__).resolve().parents[1]
        / "apps"
        / "ryoku-install-edit.py"
    )

    parser_path = Path(
        os.environ.get(
            "RYOKU_INSTALL_PARSER",
            default,
        )
    )

    spec = importlib.util.spec_from_file_location(
        "ryoku_install_edit",
        parser_path,
    )

    if spec is None or spec.loader is None:
        raise RuntimeError(
            f"could not load parser from {parser_path}"
        )

    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    return module


PARSER = load_parser()
SOURCE = "github:aethctl/Ryoku-on-NixOS/main"


class InstallerEditTests(unittest.TestCase):
    def assert_valid_nix(self, text):
        nix_instantiate = shutil.which(
            "nix-instantiate"
        )

        if not nix_instantiate:
            return

        with tempfile.NamedTemporaryFile(
            "w",
            suffix=".nix",
        ) as handle:
            handle.write(text)
            handle.flush()

            proc = subprocess.run(
                [
                    nix_instantiate,
                    "--parse",
                    handle.name,
                ],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

        self.assertEqual(
            proc.returncode,
            0,
            proc.stderr,
        )

    def assert_installed_once(
        self,
        text,
        host="host",
    ):
        edited = PARSER.edit_flake(
            text,
            host,
            SOURCE,
        )

        self.assertEqual(
            edited.count(
                "ryoku.nixosModules.default"
            ),
            1,
        )

        self.assertEqual(
            edited.count("./ryoku.nix"),
            1,
        )

        self.assertEqual(
            PARSER.edit_flake(
                edited,
                host,
                SOURCE,
            ),
            edited,
        )

        self.assert_valid_nix(edited)

        return edited

    def test_standard_multiline_flake(self):
        self.assert_installed_once(
            """{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = inputs@{ self, nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
      ];
    };
  };
}
"""
        )

    def test_inline_inputs_post_alias_and_inline_modules(self):
        edited = self.assert_installed_once(
            """{
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11"; };

  outputs = { self, nixpkgs, ... }@inputs: {
    nixosConfigurations = {
      host = nixpkgs.lib.nixosSystem {
        modules = [ ./configuration.nix ];
      };
    };
  };
}
"""
        )

        self.assertIn(
            "}@inputs:",
            edited,
        )

    def test_dotted_inputs(self):
        edited = self.assert_installed_once(
            """{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [ ./configuration.nix ];
    };
  };
}
"""
        )

        self.assertIn(
            "inputs.ryoku.url",
            edited,
        )

    def test_no_existing_inputs(self):
        self.assert_installed_once(
            """{
  outputs = { self, ... }:
    let
      nixosSystem = args: args;
    in
    {
      nixosConfigurations.host = nixosSystem {
        modules = [ ./configuration.nix ];
      };
    };
}
"""
        )

    def test_nested_modules_key_is_ignored(self):
        edited = self.assert_installed_once(
            """{
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs"; };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      specialArgs = {
        modules = [ "not-the-host-list" ];
      };

      modules = [
        ./configuration.nix
      ];
    };
  };
}
"""
        )

        self.assertIn(
            'modules = [ "not-the-host-list" ];',
            edited,
        )

    def test_does_not_wander_into_another_host(self):
        text = """{
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs"; };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations = {
      alpha = nixpkgs.lib.nixosSystem {
        modules = sharedModules;
      };

      beta = nixpkgs.lib.nixosSystem {
        modules = [ ./beta.nix ];
      };
    };
  };
}
"""

        with self.assertRaisesRegex(
            PARSER.EditError,
            "no directly editable",
        ):
            PARSER.edit_flake(
                text,
                "alpha",
                SOURCE,
            )

    def test_input_only_adds_no_modules_or_output_arguments(self):
        text = """{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      modules = [ ./configuration.nix ];
    };
  };
}
"""
        edited = PARSER.add_input(text, SOURCE)
        self.assertIn("inputs.ryoku.url", edited)
        self.assertNotIn("ryoku.nixosModules.default", edited)
        self.assertNotIn("./ryoku.nix", edited)
        self.assertIn("outputs = { self, nixpkgs }:", edited)
        self.assertEqual(PARSER.add_input(edited, SOURCE), edited)
        self.assert_valid_nix(edited)

    def test_imported_host_fails_safely(self):
        text = """{
  inputs = { nixpkgs.url = "github:NixOS/nixpkgs"; };

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations =
      import ./hosts.nix { inherit nixpkgs; };
  };
}
"""

        with self.assertRaisesRegex(
            PARSER.EditError,
            "could not safely locate",
        ):
            PARSER.edit_flake(
                text,
                "host",
                SOURCE,
            )


if __name__ == "__main__":
    unittest.main(verbosity=2)
