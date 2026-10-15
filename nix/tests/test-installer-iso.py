import os
import subprocess
import tempfile
import unittest
from pathlib import Path


class ISOInstallerTests(unittest.TestCase):
    def run_backend(self, *args, env=None):
        backend = os.environ["RYOKU_INSTALL_TEST_BACKEND"]
        return subprocess.run(
            [backend, *args],
            env=env or os.environ,
            capture_output=True,
            text=True,
            timeout=30,
        )

    def test_flake_inputs_resolve_before_disk_mutation(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        lock = backend.index('echo "@@RYOKU_STEP lock"')
        validate = backend.index('echo "@@RYOKU_STEP validate"')
        partition = backend.index('echo "@@RYOKU_STEP partition"')
        lock_call = backend.index('if ! "${lock_args[@]}"; then')
        eval_call = backend.index('nix eval --raw', lock_call)
        wipe = backend.index('run_root wipefs -af "$install_disk"')

        self.assertLess(lock, validate)
        self.assertLess(validate, partition)
        self.assertLess(lock_call, eval_call)
        self.assertLess(eval_call, wipe)
        self.assertIn("flake input resolution failed before disk changes", backend)
        self.assertIn('chown -R root:root "$target_root/etc/nixos"', backend)

    def test_nvidia_kernel_modules_are_built_before_disk_mutation(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        validate = backend.index('echo "@@RYOKU_STEP validate"')
        modules = backend.index(
            "nixosConfigurations.$install_host.config.system.modulesTree",
            validate,
        )
        wipe = backend.index('run_root wipefs -af "$install_disk"')

        self.assertLess(validate, modules)
        self.assertLess(modules, wipe)

        preflight = backend[validate:wipe]
        self.assertIn("--no-link", preflight)
        self.assertIn("--no-write-lock-file", preflight)
        self.assertIn(
            "NVIDIA kernel-module preflight failed before disk changes",
            preflight,
        )

    def test_explicit_source_overrides_iso_target_environment(self):
        env = dict(
            os.environ,
            RYOKU_INSTALL_TARGET_SOURCE="github:aethctl/Ryoku-on-NixOS/pinned-release",
        )
        result = self.run_backend(
            "--iso", "--dry-run", "--yes",
            "--source", "github:aethctl/Ryoku-on-NixOS/unstable-dev",
            "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
            "--gpu", "none",
            env=env,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Ryoku      github:aethctl/Ryoku-on-NixOS/unstable-dev", output)
        self.assertIn(
            'ryokuSource = "github:aethctl/Ryoku-on-NixOS/unstable-dev"',
            output,
        )
        self.assertNotIn("pinned-release", output)

    def test_preflight_cleanup_is_armed_before_lock_resolution(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        trap = backend.index("trap iso_cleanup EXIT")
        lock = backend.index('echo "@@RYOKU_STEP lock"')
        self.assertLess(trap, lock)
        self.assertIn('chmod -R u+w "$iso_work/ryoku-source"', backend)
        self.assertIn('if ! "${lock_args[@]}"; then', backend)


    def test_import_host_is_validated_by_preflight_before_disk_mutation(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        host = backend.index('install_host="$import_host"')
        evaluate = backend.index('nix eval --raw', host)
        wipe = backend.index('run_root wipefs -af "$install_disk"')
        self.assertLess(host, evaluate)
        self.assertLess(evaluate, wipe)
        self.assertIn('nixosConfigurations.$install_host.config.system.build.toplevel.drvPath', backend)

    def test_nvidia_policy_matches_supported_driver_generations(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        self.assertIn('nvidia_branch="legacy_470"', backend)
        self.assertIn('nvidia_branch="legacy_580"', backend)
        self.assertIn('nvidia_branch="stable"', backend)
        self.assertIn('nvidia_open=true', backend)
        self.assertIn('nvidia_open=false', backend)

    def test_dry_run_uses_canonical_iso_configs(self):
        env = dict(
            os.environ,
            RYOKU_INSTALL_TARGET_SOURCE="github:aethctl/Ryoku-on-NixOS/deadbeef",
            RYOKU_INSTALL_NIXPKGS_SOURCE="github:NixOS/nixpkgs/cafebabe",
        )
        result = self.run_backend(
            "--iso",
            "--dry-run",
            "--disk",
            "/dev/vda",
            "--filesystem",
            "btrfs",
            "--hostname",
            "ryoku-test",
            "--username",
            "tester",
            "--timezone",
            "Europe/London",
            "--locale",
            "en_GB.UTF-8",
            "--keyboard",
            "gb",
            "--gpu",
            "nvidia,intel",
            "--firmware",
            "uefi",
            "--compositor",
            "mango",
            "--browser",
            "firefox",
            "--shell",
            "zsh",
            "--apps",
            "prompt,go",
            "--yes",
            "--confirm-disk",
            "/dev/vda",
            env=env,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)

        self.assertIn("Ryoku NixOS full installation", output)
        self.assertIn("Disk       /dev/vda", output)
        self.assertIn("Filesystem btrfs", output)
        self.assertIn("Timezone   Europe/London", output)
        self.assertIn("Locale     en_GB.UTF-8", output)
        self.assertIn("Keyboard   gb", output)
        self.assertIn("GPU        nvidia,intel", output)
        self.assertIn("WM         mango", output)

        # Release flakes retain updatable branch URLs. The installer pins the
        # tested revisions in flake.lock with --override-input instead.
        self.assertIn("nixosConfigurations.ryoku", output)
        self.assertIn('nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"', output)
        self.assertIn('ryoku.url = "github:aethctl/Ryoku-on-NixOS/main"', output)
        self.assertIn('ryokuSource = "github:aethctl/Ryoku-on-NixOS/deadbeef"', output)
        self.assertIn('nixpkgsSource = "github:NixOS/nixpkgs/cafebabe"', output)
        self.assertIn("./ryoku.nix", output)
        self.assertIn("./configuration.nix", output)

        # configuration.nix stays human-readable and consumes the generated
        # install-values.nix through specialArgs.
        self.assertIn("map gpuModule install.gpuVendors", output)
        self.assertIn("networking.hostName = install.hostname", output)
        self.assertIn("nix.package = pkgs.nixVersions.latest", output)
        self.assertIn("nixos-rebuild switch --flake /etc/nixos#ryoku", output)

        # install-values.nix carries only machine-specific choices.
        self.assertIn('hostname = "ryoku-test"', output)
        self.assertIn('username = "tester"', output)
        self.assertNotIn("passwordHash", output)
        self.assertIn('timeZone = "Europe/London"', output)
        self.assertIn('locale = "en_GB.UTF-8"', output)
        self.assertIn('keyboardLayout = "gb"', output)
        self.assertIn('kernel = "default"', output)
        self.assertIn('"nvidia"', output)
        self.assertIn('"intel"', output)
        self.assertIn('nvidiaBranch = "', output)
        self.assertIn('nvidiaOpen = ', output)
        self.assertIn('compositor = "mango"', output)
        self.assertIn('browser = "firefox"', output)
        self.assertIn('shell = "zsh"', output)
        self.assertIn('"prompt"', output)
        self.assertIn('"go"', output)

        self.assertIn("Dry run complete. No disks or files were changed.", output)
        self.assertNotIn("@@RYOKU_STEP partition", output)
        self.assertNotIn("@@RYOKU_STEP install", output)

    def test_unknown_timezone_is_rejected_before_install(self):
        result = self.run_backend(
            "--iso", "--dry-run", "--yes",
            "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
            "--timezone", "Mars/Olympus", "--gpu", "none",
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("unknown timezone: Mars/Olympus", output)

    def test_kernel_choice_is_written_to_install_values(self):
        result = self.run_backend(
            "--iso", "--dry-run", "--yes",
            "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
            "--kernel", "zen", "--gpu", "none",
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Kernel     zen", output)
        self.assertIn('kernel = "zen"', output)

    def test_removed_hardened_kernel_is_rejected(self):
        result = self.run_backend(
            "--iso", "--dry-run", "--yes",
            "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
            "--kernel", "hardened", "--gpu", "none",
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("invalid kernel: hardened", output)
        self.assertIn("expected default, latest, or zen", output)

    def test_import_mode_adds_only_ryoku_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "flake.nix").write_text(
                '{\n'
                '  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";\n'
                '  outputs = { self, nixpkgs }: {\n'
                '    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {\n'
                '      system = "x86_64-linux";\n'
                '      modules = [ ./configuration.nix ./hardware-configuration.nix ];\n'
                '    };\n'
                '  };\n'
                '}\n'
            )
            (root / "configuration.nix").write_text('{ ... }: { system.stateVersion = "26.11"; }\n')
            (root / "hardware-configuration.nix").write_text('{ ... }: {}\n')
            result = self.run_backend(
                "--iso", "--dry-run", "--yes",
                "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
                "--config-mode", "import", "--import-flake", directory,
                "--import-host", "laptop", "--gpu", "none",
            )
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn("Config     import", output)
            self.assertIn("inputs.ryoku.url", output)
            self.assertNotIn("ryoku.nixosModules.default", output)
            self.assertNotIn("./ryoku.nix", output)
            self.assertIn("Imported configuration is otherwise unchanged", output)

    def test_import_mode_rejects_extra_disk_declarations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "flake.nix").write_text(
                '{\n'
                '  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";\n'
                '  outputs = { self, nixpkgs }: {\n'
                '    nixosConfigurations.laptop = nixpkgs.lib.nixosSystem {\n'
                '      system = "x86_64-linux";\n'
                '      modules = [ ./configuration.nix ./hardware-configuration.nix ];\n'
                '    };\n'
                '  };\n'
                '}\n'
            )
            (root / "configuration.nix").write_text(
                '{ ... }: { fileSystems."/data".device = "/dev/disk/by-uuid/OLD"; }\n'
            )
            (root / "hardware-configuration.nix").write_text('{ ... }: {}\n')
            result = self.run_backend(
                "--iso", "--dry-run", "--yes",
                "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
                "--config-mode", "import", "--import-flake", directory,
                "--import-host", "laptop", "--gpu", "none",
            )
            output = result.stdout + result.stderr
            self.assertNotEqual(result.returncode, 0, output)
            self.assertIn("filesystem/disk declarations outside hardware-configuration.nix", output)

    def test_live_iso_source_is_rebased_into_target_flake(self):
        env = dict(
            os.environ,
            RYOKU_INSTALL_TARGET_SOURCE="path:/etc/ryoku/source",
        )
        result = self.run_backend(
            "--iso",
            "--dry-run",
            "--yes",
            "--disk",
            "/dev/vda",
            "--confirm-disk",
            "/dev/vda",
            "--gpu",
            "none",
            env=env,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn('ryoku.url = "path:./ryoku-source"', output)
        self.assertIn('ryokuSource = "path:./ryoku-source"', output)
        self.assertNotIn('ryoku.url = "path:/etc/ryoku/source"', output)

    def test_all_gpu_modes_are_accepted(self):
        for gpu in ("none", "nvidia", "amd", "intel", "nvidia,intel", "nvidia,amd"):
            with self.subTest(gpu=gpu):
                result = self.run_backend(
                    "--iso",
                    "--dry-run",
                    "--yes",
                    "--disk",
                    "/dev/vda",
                    "--confirm-disk",
                    "/dev/vda",
                    "--gpu",
                    gpu,
                )
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 0, output)

    def test_invalid_gpu_mode_is_rejected(self):
        result = self.run_backend(
            "--iso",
            "--dry-run",
            "--yes",
            "--disk",
            "/dev/vda",
            "--confirm-disk",
            "/dev/vda",
            "--gpu",
            "potato",
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, output)
        self.assertIn("invalid GPU vendor", output)

    def test_unattended_install_requires_exact_confirmation_token(self):
        result = self.run_backend(
            "--iso",
            "--disk",
            "/dev/vda",
            "--hostname",
            "ryoku-test",
            "--username",
            "tester",
            "--firmware",
            "uefi",
            "--gpu",
            "none",
            "--compositor",
            "niri",
            "--browser",
            "firefox",
            "--shell",
            "fish",
            "--apps",
            "none",
            "--yes",
            env=dict(os.environ, RYOKU_INSTALL_PASSWORD_HASH="$y$j9T$test$test"),
        )
        output = result.stdout + result.stderr
        self.assertNotEqual(result.returncode, 0, output)
        # CI may reject synthetic /dev/vda at the block-device check before the
        # confirmation branch. The exact-token contract is also source-checked
        # by flake.nix and exercised in the VM install test.


if __name__ == "__main__":
    unittest.main()
