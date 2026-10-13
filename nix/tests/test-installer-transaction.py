import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


FLAKE = """{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ ./configuration.nix ];
    };
  };
}
"""


class TransactionTests(unittest.TestCase):
    def run_case(self, failure, existing=False, baseline_valid=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            host = root / "host"
            host.mkdir()
            (host / "flake.nix").write_text(FLAKE)
            (host / "configuration.nix").write_text("{ ... }: {}\n")
            if existing:
                (host / "flake.lock").write_text("old lock\n")
                (host / "ryoku.nix").write_text("# Managed by ryoku-install.\n{}\n")
            before = {p.name: p.read_bytes() for p in host.iterdir()}
            bindir = root / "bin"
            bindir.mkdir()
            backend = Path(os.environ["RYOKU_INSTALL_TEST_BACKEND"]).read_text()
            shell = backend.splitlines()[0][2:]

            def script(name, text):
                path = bindir / name
                path.write_text("#!" + shell + "\nset -eu\n" + text)
                path.chmod(0o755)
                return path

            script(
                "nix",
                'while [ "$#" -gt 0 ]; do\n'
                '  case "$1" in\n'
                '    --extra-experimental-features) shift 2 ;;\n'
                '    eval) echo validate >> "$TEST_CALLS"; [ "$TEST_BASELINE_VALID" = 1 ]; exit $? ;;\n'
                '    flake) echo lock >> "$TEST_CALLS"; [ "$TEST_FAILURE" != lock ]; exit $? ;;\n'
                '    *) shift ;;\n'
                '  esac\n'
                'done\n'
                'exit 2\n',
            )
            script("nixos-rebuild", 'echo "$1" >> "$TEST_CALLS"\n'
                   'if [ "$TEST_FAILURE" = interrupt ]; then kill -TERM "$PPID"; exit 1; fi\n'
                   '[ "$TEST_FAILURE" != "$1" ]\n')
            script("systemctl", "exit 0\n")
            backend = re.sub(
                r"(?ms)^[ \t]*run_root\(\) \{.*?^[ \t]*\}",
                'run_root() { "$@"; }',
                backend,
                count=1,
            )
            backend = backend.replace('/run/current-system/sw/bin', str(bindir))
            backend = backend.replace('/var/backups/ryoku-nixos', str(root / "backups"))
            backend = backend.replace(
                'set -euo pipefail',
                'export PATH="' + str(bindir) + ':$PATH"\nset -euo pipefail',
                1,
            )
            test_backend = script("backend", backend.partition("\n")[2])
            calls = root / "calls"
            env = dict(
                os.environ,
                TEST_CALLS=str(calls),
                TEST_FAILURE=failure,
                TEST_BASELINE_VALID="1" if baseline_valid else "0",
            )
            result = subprocess.run([str(test_backend), "--flake", str(host) + "#host",
                                     "--compositor", "niri", "--browser", "firefox",
                                     "--shell", "zsh", "--apps", "none", "--yes"],
                                    env=env, capture_output=True, text=True, timeout=20)
            if not baseline_valid:
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                after = {p.name: p.read_bytes() for p in host.iterdir()}
                self.assertEqual(after, before, result.stdout + result.stderr)
                self.assertEqual(calls.read_text().splitlines(), ["validate"])
                self.assertIn("existing NixOS host does not evaluate", result.stderr)
            elif failure:
                self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                after = {p.name: p.read_bytes() for p in host.iterdir()}
                self.assertEqual(after, before, result.stdout + result.stderr)
                if failure in ("lock", "build"):
                    self.assertNotIn("switch", calls.read_text().splitlines())
            else:
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(calls.read_text().splitlines(), ["validate", "lock", "build", "switch"])
                self.assertIn('defaultCompositor = "niri"', (host / "ryoku.nix").read_text())

    def test_success(self):
        self.run_case("")

    def test_broken_existing_host_aborts_before_transaction(self):
        for existing in (False, True):
            with self.subTest(existing=existing):
                self.run_case("", existing=existing, baseline_valid=False)

    def test_failures_restore_new_and_existing_configs(self):
        for failure in ("lock", "build", "switch", "interrupt"):
            for existing in (False, True):
                with self.subTest(failure=failure, existing=existing):
                    self.run_case(failure, existing)


if __name__ == "__main__":
    unittest.main()
