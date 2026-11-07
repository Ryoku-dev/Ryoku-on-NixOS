import os
import shutil
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
            RYOKU_INSTALL_TARGET_SOURCE="github:Ryoku-dev/Ryoku-on-NixOS/pinned-release",
        )
        result = self.run_backend(
            "--iso", "--dry-run", "--yes",
            "--source", "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
            "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
            "--gpu", "none",
            env=env,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("Ryoku      github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev", output)
        self.assertIn(
            'ryokuSource = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev"',
            output,
        )
        self.assertNotIn("pinned-release", output)

    def test_failed_cleanup_reports_mount_problem_without_forced_detach(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        cleanup = backend.split("  iso_cleanup() {", 1)[1].split("\n  }", 1)[0]
        self.assertIn('findmnt -rn --mountpoint "$target_root"', cleanup)
        self.assertIn('if ! run_root umount -R "$target_root"', cleanup)
        self.assertIn('WARNING: could not unmount', cleanup)
        self.assertNotIn('umount -Rl', cleanup)
        self.assertNotIn('swapoff -a', cleanup)
        self.assertIn('an earlier installation may be incomplete', backend)

    def test_failure_after_repartitioning_says_the_disk_was_modified(self):
        backend = Path(os.environ["RYOKU_INSTALL_BACKEND_SOURCE"]).read_text()
        cleanup = backend.split("  iso_cleanup() {", 1)[1].split("\n  }", 1)[0]
        self.assertIn('"${disk_modified:-0}" -eq 1', cleanup)
        self.assertIn("INSTALLATION DID NOT COMPLETE", cleanup)
        self.assertIn("Do not reboot into it", cleanup)
        # Never promise to undo disk changes.
        self.assertNotIn("rollback", cleanup.lower())
        self.assertNotIn("restore", cleanup.lower())
        # The flag flips only after the last confirmation and identity
        # revalidation, immediately before the first destructive command.
        flag = backend.index("  disk_modified=1\n")
        self.assertLess(backend.index('revalidate_install_disk "$install_disk"'), flag)
        self.assertLess(backend.index("Type the exact disk path"), flag)
        self.assertLess(flag, backend.index('run_root wipefs -af "$install_disk"'))
        # It is global, not function-local, so the EXIT trap can read it.
        self.assertNotIn("local disk_modified", backend)
        # Cleared again on success so a clean finish is never reported as failed.
        self.assertLess(backend.index('run_root umount -R "$target_root"\n\n  disk_modified=0'),
                        backend.index('echo "@@RYOKU_DONE"\n  printf \'\\nRyoku installation complete'))

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
            RYOKU_INSTALL_TARGET_SOURCE="github:Ryoku-dev/Ryoku-on-NixOS/deadbeef",
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
        self.assertIn('ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/main"', output)
        self.assertIn("Follows    github:Ryoku-dev/Ryoku-on-NixOS/main", output)
        self.assertIn('ryokuSource = "github:Ryoku-dev/Ryoku-on-NixOS/deadbeef"', output)
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

    def test_installed_flake_follows_iso_track(self):
        env = dict(
            os.environ,
            RYOKU_INSTALL_TARGET_SOURCE="github:Ryoku-dev/Ryoku-on-NixOS/deadbeef",
            RYOKU_INSTALL_TARGET_TRACK="github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
        )
        result = self.run_backend(
            "--iso", "--dry-run", "--yes",
            "--disk", "/dev/vda", "--confirm-disk", "/dev/vda",
            "--gpu", "none",
            env=env,
        )
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        # flake.nix follows the ISO's branch; the lock step pins deadbeef.
        self.assertIn('ryoku.url = "github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev";', output)
        self.assertIn("Ryoku      github:Ryoku-dev/Ryoku-on-NixOS/deadbeef", output)
        self.assertIn("Follows    github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev", output)
        self.assertIn('ryokuSource = "github:Ryoku-dev/Ryoku-on-NixOS/deadbeef"', output)
        self.assertNotIn("Ryoku-on-NixOS/main", output)

    def test_live_iso_source_is_rebased_into_target_flake(self):
        env = dict(
            os.environ,
            RYOKU_INSTALL_TARGET_SOURCE="path:/etc/ryoku/source",
            RYOKU_INSTALL_TARGET_TRACK="github:Ryoku-dev/Ryoku-on-NixOS/unstable-dev",
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
        self.assertIn("Follows    path:./ryoku-source", output)
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


GIB = 1024 * 1024 * 1024
DRV = "/nix/store/" + "a" * 32 + "-nixos-system-ryoku.drv"


def plan_text(builds, unpacked):
    lines = []
    if builds:
        lines.append(f"these {len(builds)} derivations will be built:")
        lines += [f"  /nix/store/{'b' * 32}-{name}.drv" for name in builds]
    if unpacked:
        lines.append(f"these 2164 paths will be fetched (7.1 GiB download, {unpacked} unpacked):")
        lines.append(f"  /nix/store/{'c' * 32}-glibc-2.42")
    return "\n".join(lines) + "\n"


STUBS = {
    # Only the subcommands the ISO path uses before the disk is erased.
    "nix": r"""
case "$1 $2" in
  "flake lock") exit 0 ;;
  "eval --raw") printf '%s' "$STUB_DRV" ;;
  "config show") printf '%s\n' "$STUB_SUBSTITUTERS" ;;
  "copy --no-check-sigs") exit "${STUB_COPY_RC:-0}" ;;
  "build --dry-run")
    printf 'nix %s\n' "$*" >> "$STUB_LOG"
    cat "$STUB_PLAN"
    exit "${STUB_PLAN_RC:-0}"
    ;;
  *) printf 'unexpected nix %s\n' "$*" >&2; exit 97 ;;
esac
""",
    "curl": r"""
for arg; do url=$arg; done
case " $STUB_DOWN " in *" ${url%/nix-cache-info} "*) exit 7 ;; esac
exit 0
""",
    "lsblk": r"""
case "$*" in
  *TYPE*) echo disk ;;
  *RO*) echo 0 ;;
  *MAJ:MIN*) echo 253:0 ;;
  *MODEL*) echo 'Test disk' ;;
  *MOUNTPOINTS*) : ;;
  *SIZE*) echo "$STUB_DISK_BYTES" ;;
  *PKNAME*) : ;;
  *) exit 1 ;;
esac
""",
    "udevadm": "printf 'ID_SERIAL=RYOKUTEST\\n'\n",
    "findmnt": "exit 1\n",
    "id": "echo 0\n",
    # Reaching any of these means the disk would have been modified.
    "wipefs": 'printf "wipefs %s\\n" "$*" >> "$STUB_LOG"; exit 1\n',
    "parted": 'printf "parted %s\\n" "$*" >> "$STUB_LOG"; exit 1\n',
    "sgdisk": 'printf "sgdisk %s\\n" "$*" >> "$STUB_LOG"; exit 1\n',
}


class ISOPreflightPlanTests(unittest.TestCase):
    """Run the packaged backend's real --iso path (not --dry-run) with every
    disk/Nix command stubbed, to prove the install plan is checked before the
    first destructive command."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        stubs = self.tmp / "stubs"
        stubs.mkdir()
        bash = shutil.which("bash")
        for name, body in STUBS.items():
            path = stubs / name
            path.write_text(f"#!{bash}\n{body}")
            path.chmod(0o755)
        backend = Path(os.environ["RYOKU_INSTALL_TEST_BACKEND"]).read_text()
        marker = 'export PATH="'
        self.assertIn(marker, backend)
        self.script = self.tmp / "backend"
        self.script.write_text(backend.replace(marker, f'{marker}{stubs}:', 1))
        self.log = self.tmp / "calls.log"
        self.log.touch()
        self.plan = self.tmp / "plan.txt"
        self.env = dict(
            os.environ,
            STUB_LOG=str(self.log),
            STUB_PLAN=str(self.plan),
            STUB_DRV=DRV,
            STUB_SUBSTITUTERS="https://cache.nixos.org/",
            STUB_DOWN="",
            STUB_DISK_BYTES=str(40 * GIB),
            RYOKU_INSTALL_PASSWORD_HASH="$y$j9T$test$test",
            RYOKU_INSTALL_TARGET_SOURCE="github:Ryoku-dev/Ryoku-on-NixOS/deadbeef",
            RYOKU_INSTALL_TARGET_ROOT=str(self.tmp / "mnt"),
            # The sandbox has no block devices; make only the fake disk one.
            **{"BASH_FUNC_[%%": '() { if [[ $1 == -b && $2 == /dev/fake* ]]; then return 0; fi; builtin [ "$@"; }'},
        )

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def install(self, plan, **env):
        self.plan.write_text(plan)
        result = subprocess.run(
            [shutil.which("bash"), str(self.script),
             "--iso", "--yes", "--disk", "/dev/fakedisk", "--confirm-disk", "/dev/fakedisk",
             "--firmware", "uefi", "--gpu", "none", "--apps", "none"],
            env=dict(self.env, **env), capture_output=True, text=True, timeout=60,
        )
        return result.stdout + result.stderr, self.log.read_text()

    def assertDiskUntouched(self, calls, output):
        for command in ("wipefs", "parted", "sgdisk"):
            self.assertNotIn(command, calls, output)
        self.assertIn("No disk changes were made", output)

    def test_plan_that_fits_reaches_the_disk_steps(self):
        output, calls = self.install(plan_text(["etc", "system-path"], "15.0 GiB"))
        self.assertIn("nix build --dry-run", calls, output)
        self.assertIn("wipefs -af /dev/fakedisk", calls, output)
        self.assertIn("Packages built on this machine: 2", output)

    def test_plan_larger_than_the_disk_is_refused_before_wiping(self):
        output, calls = self.install(plan_text(["etc"], "35.0 GiB"))
        self.assertIn("nix build --dry-run", calls, output)
        self.assertDiskUntouched(calls, output)
        self.assertIn("/dev/fakedisk is too small for this installation", output)

    def test_unreachable_substituter_is_refused_before_wiping(self):
        output, calls = self.install(
            plan_text(["etc"], "15.0 GiB"),
            STUB_SUBSTITUTERS="https://cache.nixos.org/ https://cache.example.org",
            STUB_DOWN="https://cache.example.org",
        )
        self.assertDiskUntouched(calls, output)
        self.assertIn("binary cache https://cache.example.org did not answer", output)

    def test_failed_plan_is_refused_before_wiping(self):
        output, calls = self.install("error: unable to download narinfo\n", STUB_PLAN_RC="1")
        self.assertDiskUntouched(calls, output)
        self.assertIn("could not work out what the installation needs", output)

    def test_heavy_local_builds_are_listed_without_a_new_prompt(self):
        output, calls = self.install(plan_text(
            ["hyprland-0.57.0", "hyprland-0.57.0_fish-completions", "niri-26.04",
             "linux-6.18.59-modules-shrunk", "etc"],
            "15.0 GiB",
        ))
        self.assertIn("will be\ncompiled on this machine", output)
        self.assertIn("  hyprland-0.57.0\n", output)
        self.assertIn("  niri-26.04\n", output)
        self.assertNotIn("  hyprland-0.57.0_fish-completions", output)
        self.assertNotIn("  linux-6.18.59-modules-shrunk", output)
        # Informational only: the unattended install still proceeds.
        self.assertIn("wipefs -af /dev/fakedisk", calls, output)


if __name__ == "__main__":
    unittest.main()
