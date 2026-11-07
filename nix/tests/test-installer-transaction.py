import os
from pathlib import Path
import re
import shutil
import signal
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

# What a failed `nixos-rebuild build` prints when the new configuration does
# not evaluate. The installer must pass it through, not replace it.
NIX_ERROR = (
    "error:\n"
    "       … while evaluating the option `system.build.toplevel':\n"
    "       error: infinite recursion encountered\n"
)


def default_signals():
    # Signals ignored by the test runner would stay ignored in the backend and
    # make its traps unreachable; start it the way a terminal would.
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, signal.SIG_DFL)


class TransactionTests(unittest.TestCase):
    def install(self, root, host, failure="", baseline_valid=True, gpu="none",
                flake_arg=None, generated_flake=False, restore="", answer=None,
                extra_args=()):
        """Run the existing-NixOS install path against fake Nix tools.

        Returns (result, calls, rebuild_args, tmpdir). `generated_flake`
        treats `host` as /etc/nixos without a flake.nix; `restore` makes the
        restore copies fail ("fail") or delivers a second Ctrl+C
        ("interrupt") or a closing terminal ("hangup") while they run.
        Calling it again with the same root retries, as the TUI's "r" does.
        """
        bindir = root / "bin"
        bindir.mkdir(exist_ok=True)
        tmpdir = root / "tmp"
        tmpdir.mkdir(exist_ok=True)
        backups = root / "backups"
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
            '    build) echo nvidia-preflight >> "$TEST_CALLS"; [ "$TEST_FAILURE" != nvidia-preflight ]; exit $? ;;\n'
            '    flake)\n'
            '      if [ "$2" = show ]; then\n'
            '        echo show >> "$TEST_CALLS"\n'
            '        echo \'{"nixosConfigurations":{"host":{}}}\'\n'
            '        exit 0\n'
            '      fi\n'
            '      echo lock >> "$TEST_CALLS"; [ "$TEST_FAILURE" != lock ]; exit $? ;;\n'
            '    *) shift ;;\n'
            '  esac\n'
            'done\n'
            'exit 2\n',
        )
        script(
            "nixos-rebuild",
            'echo "$1" >> "$TEST_CALLS"\n'
            'echo "$*" >> "$TEST_REBUILD_ARGS"\n'
            'case "$TEST_FAILURE" in\n'
            '  interrupt) kill -TERM "$PPID"; exit 1 ;;\n'
            '  hangup) kill -HUP "$PPID"; exit 1 ;;\n'
            # Ctrl+C reaches the whole foreground process group.
            '  ctrl-c) kill -INT 0 ;;\n'
            'esac\n'
            'if [ "$TEST_FAILURE" = "$1" ]; then printf "%s" "$TEST_NIX_ERROR" >&2; exit 1; fi\n',
        )
        script(
            "cp",
            'if [ "$1" = -a ]; then\n'
            '  case "$TEST_RESTORE:$2" in\n'
            '    fail:"$TEST_BACKUPS"/*)\n'
            '      echo "cp: cannot create regular file: Read-only file system" >&2\n'
            '      exit 1 ;;\n'
            '    interrupt:"$TEST_BACKUPS"/*/flake.nix) kill -INT 0 ;;\n'
            '    hangup:"$TEST_BACKUPS"/*/flake.nix) kill -HUP 0 ;;\n'
            '  esac\n'
            'fi\n'
            'exec "$TEST_REAL_CP" "$@"\n',
        )
        script("systemctl", "exit 0\n")
        script("ryoku-materialize", 'echo materialize >> "$TEST_CALLS"\n'
               '[ "$TEST_FAILURE" != materialize ]\n')
        hostname = root / "hostname"
        hostname.write_text("host\n")
        backend = re.sub(
            r"(?ms)^[ \t]*run_root\(\) \{.*?^[ \t]*\}",
            'run_root() { "$@"; }',
            backend,
            count=1,
        )
        backend = backend.replace('/run/current-system/sw/bin', str(bindir))
        backend = backend.replace('/var/backups/ryoku-nixos', str(backups))
        backend = backend.replace('/proc/sys/kernel/hostname', str(hostname))
        if generated_flake:
            backend = backend.replace('[ "$flake_root" = "/etc/nixos" ]',
                                      '[ "$flake_root" = "' + str(host.resolve()) + '" ]')
        backend = backend.replace(
            'set -euo pipefail',
            'export PATH="' + str(bindir) + ':$PATH"\nset -euo pipefail',
            1,
        )
        test_backend = script("backend", backend.partition("\n")[2])
        calls = root / "calls"
        rebuild_args = root / "rebuild-args"
        calls.write_text("")
        rebuild_args.write_text("")
        env = dict(
            os.environ,
            TMPDIR=str(tmpdir),
            TEST_CALLS=str(calls),
            TEST_REBUILD_ARGS=str(rebuild_args),
            TEST_FAILURE=failure,
            TEST_BASELINE_VALID="1" if baseline_valid else "0",
            TEST_NIX_ERROR=NIX_ERROR,
            TEST_RESTORE=restore,
            TEST_BACKUPS=str(backups),
            TEST_REAL_CP=shutil.which("cp"),
        )
        args = [str(test_backend), "--flake", flake_arg or str(host) + "#host",
                "--compositor", "niri", "--browser", "firefox",
                "--shell", "zsh", "--apps", "none", "--gpu", gpu, *extra_args]
        if answer is None:
            args.append("--yes")
        result = subprocess.run(args, env=env, capture_output=True, text=True,
                                input=answer, timeout=20, start_new_session=True,
                                preexec_fn=default_signals)
        return (result, calls.read_text().splitlines(),
                rebuild_args.read_text().splitlines(), tmpdir)

    def snapshot(self, host):
        return {p.name: (p.read_bytes(), p.stat().st_mode) for p in host.iterdir()}

    def run_case(self, failure, existing=False, baseline_valid=True, gpu="none"):
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
            result, calls, _, tmpdir = self.install(
                root, host, failure, baseline_valid=baseline_valid, gpu=gpu)
            output = result.stdout + result.stderr
            self.assertEqual(list(tmpdir.iterdir()), [], output)
            if not baseline_valid:
                self.assertNotEqual(result.returncode, 0, output)
                after = {p.name: p.read_bytes() for p in host.iterdir()}
                self.assertEqual(after, before, output)
                self.assertEqual(calls, ["validate"])
                self.assertIn("existing NixOS host does not evaluate", result.stderr)
            elif failure == "materialize":
                # The new generation is already live: this is a warning, not a
                # failed installation, and the configuration must be kept.
                self.assertEqual(result.returncode, 0, output)
                self.assertIn("@@RYOKU_DONE", result.stdout)
                self.assertIn("WARNING: ryoku-materialize failed", result.stderr)
                self.assertIn("ryoku-materialize", result.stderr.split("WARNING", 1)[1])
                self.assertIn('defaultCompositor = "niri"', (host / "ryoku.nix").read_text())
                self.assertEqual(calls, ["validate", "lock", "build", "switch", "materialize"])
            elif failure:
                self.assertNotEqual(result.returncode, 0, output)
                after = {p.name: p.read_bytes() for p in host.iterdir()}
                self.assertEqual(after, before, output)
                if failure in ("lock", "build"):
                    self.assertNotIn("switch", calls)
                if failure == "switch":
                    # A failed activation may already have updated the system
                    # profile and boot entries: say so and say how to inspect it.
                    self.assertIn("nixos-rebuild list-generations", result.stderr)
                    self.assertIn("--rollback", result.stderr)
                    self.assertIn("configuration files restored", result.stderr)
                if failure == "nvidia-preflight":
                    self.assertEqual(calls, ["validate", "nvidia-preflight"])
                    self.assertIn(
                        "existing NixOS NVIDIA/kernel combination does not build",
                        result.stderr,
                    )
            else:
                self.assertEqual(result.returncode, 0, output)
                self.assertEqual(calls, ["validate", "lock", "build", "switch", "materialize"])
                self.assertIn('defaultCompositor = "niri"', (host / "ryoku.nix").read_text())

    def test_success(self):
        self.run_case("")

    def test_broken_existing_host_aborts_before_transaction(self):
        for existing in (False, True):
            with self.subTest(existing=existing):
                self.run_case("", existing=existing, baseline_valid=False)

    def test_nvidia_kernel_module_preflight_aborts_before_transaction(self):
        self.run_case("nvidia-preflight", gpu="nvidia")

    def test_materialize_failure_after_switch_is_not_an_install_failure(self):
        for existing in (False, True):
            with self.subTest(existing=existing):
                self.run_case("materialize", existing)

    def test_failures_restore_new_and_existing_configs(self):
        for failure in ("lock", "build", "switch", "interrupt", "hangup"):
            for existing in (False, True):
                with self.subTest(failure=failure, existing=existing):
                    self.run_case(failure, existing)

    def test_build_failure_shows_nix_error_and_never_activates(self):
        # The reported failure: the Ryoku-integrated host does not evaluate
        # at `@@RYOKU_STEP build`. Only `nixos-rebuild build` may run; the
        # real Nix error must reach the user next to the installer's verdict.
        for existing in (False, True):
            with self.subTest(existing=existing), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                host = root / "host"
                host.mkdir()
                (host / "flake.nix").write_text(FLAKE)
                (host / "configuration.nix").write_text("{ ... }: {}\n")
                (host / "hardware-configuration.nix").write_text("{ ... }: {}\n")
                if existing:
                    (host / "flake.lock").write_text("old lock\n")
                    (host / "ryoku.nix").write_text("# Managed by ryoku-install.\n{}\n")
                    (host / "flake.lock").chmod(0o600)
                before = self.snapshot(host)
                result, calls, rebuild_args, tmpdir = self.install(root, host, "build")
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 1, output)
                self.assertEqual(self.snapshot(host), before, output)
                self.assertEqual(calls, ["validate", "lock", "build"])
                self.assertEqual(rebuild_args,
                                 ["build --flake path:" + str(host.resolve()) + "#host"])
                self.assertIn("@@RYOKU_STEP build", result.stdout)
                self.assertNotIn("@@RYOKU_STEP switch", result.stdout)
                self.assertNotIn("@@RYOKU_DONE", result.stdout)
                self.assertIn(NIX_ERROR, result.stderr)
                self.assertIn("ryoku-install: build failed; files restored", result.stderr)
                self.assertLess(result.stderr.index(NIX_ERROR),
                                result.stderr.index("build failed; files restored"))
                self.assertEqual(list(tmpdir.iterdir()), [], output)

    def test_non_flake_host_keeps_no_generated_flake_after_failure(self):
        # A classic /etc/nixos (configuration.nix, no flake.nix) gets a
        # generated base flake. If the install does not complete, that flake
        # must not stay behind: a later plain `nixos-rebuild switch` would
        # silently build from it instead of from the user's channels.
        cases = [
            dict(failure="build"),
            dict(failure="lock"),
            dict(failure="switch"),
            dict(failure="interrupt"),
            dict(failure="", baseline_valid=False),
            dict(failure="", answer="n\n"),
        ]
        for case in cases:
            with self.subTest(**case), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                host = root / "host"
                host.mkdir()
                (host / "configuration.nix").write_text("{ ... }: {}\n")
                (host / "hardware-configuration.nix").write_text("{ ... }: {}\n")
                before = self.snapshot(host)
                result, calls, _, tmpdir = self.install(
                    root, host, flake_arg=str(host), generated_flake=True, **case)
                output = result.stdout + result.stderr
                self.assertIn("created a base flake", output)
                self.assertIn("show", calls)
                if case.get("answer"):
                    self.assertIn("Cancelled.", result.stdout)
                    self.assertEqual(calls, ["show", "validate"])
                else:
                    self.assertNotEqual(result.returncode, 0, output)
                self.assertEqual(self.snapshot(host), before, output)
                self.assertEqual(list(tmpdir.iterdir()), [], output)

    def test_non_flake_host_keeps_generated_flake_after_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            host = root / "host"
            host.mkdir()
            (host / "configuration.nix").write_text("{ ... }: {}\n")
            (host / "hardware-configuration.nix").write_text("{ ... }: {}\n")
            result, calls, _, _ = self.install(
                root, host, flake_arg=str(host), generated_flake=True)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertEqual(calls, ["show", "validate", "lock", "build", "switch", "materialize"])
            self.assertIn("./ryoku.nix", (host / "flake.nix").read_text())
            self.assertTrue((host / "ryoku.nix").is_file(), output)

    def test_failed_restore_names_the_backup(self):
        # If restoring itself fails, the installer must not claim the files
        # were restored and must say where the untouched originals are.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            host = root / "host"
            host.mkdir()
            (host / "flake.nix").write_text(FLAKE)
            (host / "configuration.nix").write_text("{ ... }: {}\n")
            (host / "flake.lock").write_text("old lock\n")
            result, calls, _, tmpdir = self.install(root, host, "build", restore="fail")
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 1, output)
            self.assertNotIn("files restored", result.stderr)
            self.assertIn(NIX_ERROR, result.stderr)
            self.assertIn("build failed", result.stderr)
            backup = next((root / "backups").iterdir())
            self.assertIn(str(backup), result.stderr)
            self.assertEqual((backup / "flake.nix").read_text(), FLAKE)
            self.assertEqual((backup / "flake.lock").read_text(), "old lock\n")
            # What can still be undone is undone: the new ryoku.nix did not
            # exist before and is removed.
            self.assertFalse((host / "ryoku.nix").exists(), output)
            self.assertNotIn("switch", calls)
            self.assertEqual(list(tmpdir.iterdir()), [], output)

    def failed_restore_host(self, root, existing):
        """A host whose install failed and whose restore failed with it."""
        host = root / "host"
        host.mkdir()
        (host / "flake.nix").write_text(FLAKE)
        (host / "configuration.nix").write_text("{ ... }: {}\n")
        if existing:
            (host / "flake.lock").write_text("old lock\n")
            (host / "ryoku.nix").write_text("# Managed by ryoku-install.\n{}\n")
        before = self.snapshot(host)
        result, _, _, _ = self.install(root, host, "build", restore="fail")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotEqual(self.snapshot(host), before)
        return host, before

    def test_retry_after_failed_restore_starts_from_the_original(self):
        # After a failed restore /etc/nixos is a mix of old and new files. A
        # retry must put the originals back before anything else, not back
        # up the mix as if it were the user's configuration.
        for retry, existing in [(r, e) for r in ("build", "") for e in (False, True)]:
            with (self.subTest(retry=retry or "success", existing=existing),
                  tempfile.TemporaryDirectory() as directory):
                root = Path(directory)
                host, before = self.failed_restore_host(root, existing)
                original = next((root / "backups").iterdir())
                result, calls, _, _ = self.install(root, host, retry)
                output = result.stdout + result.stderr
                # The first backup is never replaced.
                self.assertEqual((original / "flake.nix").read_text(), FLAKE, output)
                if retry:
                    self.assertEqual(result.returncode, 1, output)
                    self.assertEqual(self.snapshot(host), before, output)
                    self.assertIn("files restored", result.stderr)
                else:
                    self.assertEqual(result.returncode, 0, output)
                    self.assertEqual(calls, ["validate", "lock", "build", "switch", "materialize"])
                    backup = Path(output.rpartition("Backup: ")[2].strip())
                    self.assertNotEqual(backup, original, output)
                    self.assertEqual((backup / "flake.nix").read_text(), FLAKE, output)
                    # Installed: the next run is an ordinary reinstall.
                    rerun, _, _, _ = self.install(root, host, "build")
                    self.assertNotIn("restoring it from", rerun.stdout + rerun.stderr)
                    self.assertIn("./ryoku.nix", (host / "flake.nix").read_text())
                self.assertIn("restoring it from " + str(original), output)

    def test_retry_changes_nothing_while_the_originals_cannot_be_restored(self):
        for existing in (False, True):
            with (self.subTest(existing=existing),
                  tempfile.TemporaryDirectory() as directory):
                root = Path(directory)
                host, _ = self.failed_restore_host(root, existing)
                original = next((root / "backups").iterdir())
                mixed = self.snapshot(host)
                result, calls, _, _ = self.install(root, host, "", restore="fail")
                output = result.stdout + result.stderr
                self.assertEqual(result.returncode, 1, output)
                self.assertEqual(calls, [], output)
                self.assertEqual(self.snapshot(host), mixed, output)
                self.assertEqual([p.name for p in (root / "backups").iterdir()
                                  if p.is_dir()], [original.name])
                self.assertIn(str(original), result.stderr)
                self.assertIn("--manual-recovery", result.stderr)
                self.assertNotIn("@@RYOKU_STEP", result.stdout)

    def test_lock_serializes_installs_and_releases_after_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            host = root / "host"
            host.mkdir()
            (host / "flake.nix").write_text(FLAKE)
            (host / "configuration.nix").write_text("{ ... }: {}\n")
            before = self.snapshot(host)
            lock = root / "backups" / ".install-active"
            lock.mkdir(parents=True)

            blocked, calls, _, _ = self.install(root, host)
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn("another Ryoku installation", blocked.stderr)
            self.assertEqual(calls, [])
            self.assertEqual(self.snapshot(host), before)
            self.assertTrue(lock.is_dir())

            lock.rmdir()
            failed, calls, _, _ = self.install(root, host, "build")
            self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
            self.assertEqual(calls, ["validate", "lock", "build"])
            self.assertFalse(lock.exists())
            self.assertEqual(self.snapshot(host), before)

            succeeded, calls, _, _ = self.install(root, host)
            self.assertEqual(succeeded.returncode, 0, succeeded.stdout + succeeded.stderr)
            self.assertFalse(lock.exists())

    def test_unresolved_restore_blocks_a_different_flake(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            damaged, _ = self.failed_restore_host(root, existing=True)
            pending = root / "backups.restore-pending"
            record = pending.read_bytes()
            original = next((root / "backups").iterdir())
            other = root / "other-host"
            other.mkdir()
            (other / "flake.nix").write_text(FLAKE)
            (other / "configuration.nix").write_text("{ ... }: {}\n")
            before = self.snapshot(other)

            for extra_args in ((), ("--manual-recovery",)):
                with self.subTest(extra_args=extra_args):
                    result, calls, _, _ = self.install(
                        root, other, extra_args=extra_args)
                    output = result.stdout + result.stderr
                    self.assertEqual(result.returncode, 1, output)
                    self.assertIn(str(damaged), result.stderr)
                    self.assertIn(str(original), result.stderr)
                    self.assertIn(str(other), result.stderr)
                    self.assertEqual(calls, [], output)
                    self.assertEqual(self.snapshot(other), before, output)
                    self.assertEqual(pending.read_bytes(), record, output)
                    self.assertEqual((original / "flake.nix").read_text(), FLAKE)

    def test_manual_recovery_is_an_explicit_choice(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            host, before = self.failed_restore_host(root, existing=True)
            original = next((root / "backups").iterdir())
            # The user copies the originals back by hand and says so.
            for name in ("flake.nix", "flake.lock", "ryoku.nix"):
                shutil.copyfile(original / name, host / name)
            result, calls, _, _ = self.install(
                root, host, "build", extra_args=["--manual-recovery"])
            output = result.stdout + result.stderr
            self.assertNotIn("restoring it from", output)
            self.assertIn("build failed", result.stderr)
            self.assertEqual(calls, ["validate", "lock", "build"])
            self.assertEqual((original / "flake.nix").read_text(), FLAKE)
            self.assertEqual({k: v[0] for k, v in self.snapshot(host).items()},
                             {k: v[0] for k, v in before.items()})

    def test_second_ctrl_c_does_not_interrupt_the_restore(self):
        # Ctrl+C during a long build is often pressed twice. The second one
        # must not stop the restore half-way and leave a mixed configuration;
        # neither may the terminal closing at that moment.
        for second, existing in [(s, e) for s in ("interrupt", "hangup") for e in (False, True)]:
            with (self.subTest(second=second, existing=existing),
                  tempfile.TemporaryDirectory() as directory):
                root = Path(directory)
                host = root / "host"
                host.mkdir()
                (host / "flake.nix").write_text(FLAKE)
                (host / "configuration.nix").write_text("{ ... }: {}\n")
                if existing:
                    (host / "flake.lock").write_text("old lock\n")
                    (host / "ryoku.nix").write_text("# Managed by ryoku-install.\n{}\n")
                before = self.snapshot(host)
                result, calls, _, tmpdir = self.install(
                    root, host, "ctrl-c", restore=second)
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, output)
                self.assertEqual(self.snapshot(host), before, output)
                self.assertNotIn("switch", calls)
                self.assertEqual(list(tmpdir.iterdir()), [], output)


if __name__ == "__main__":
    unittest.main()
