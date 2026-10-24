#!/usr/bin/env python3
import os
import pathlib
import subprocess
import tempfile
import unittest


INSTALLER = pathlib.Path(
    os.environ.get(
        "RYOKU_QYLOCK_TEST_INSTALLER",
        pathlib.Path(__file__).parents[2] / "ryoku/lockscreen/install-qylock",
    )
)


class QylockStagingCleanupTest(unittest.TestCase):
    def test_failed_stage_removes_private_staging_tree(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            home = root / "home"
            runtime = root / "runtime"
            bundle = root / "bundle"
            lock = bundle / "quickshell-lockscreen"
            theme = bundle / "themes/clockwork/orbital"

            home.mkdir()
            runtime.mkdir()
            lock.mkdir(parents=True)
            theme.mkdir(parents=True)

            for name in ("lock.sh", "unlock.sh", "ryoku-qylock-unlock-prepare"):
                path = lock / name
                path.write_text("#!/usr/bin/env bash\nexit 0\n")
                path.chmod(0o755)
            (theme / "Main.qml").write_text("import QtQuick\nItem {}\n")

            # Reproduce the Nix-store failure shape: cp -a preserves a
            # read-only directory, so creating themes_link inside the copied
            # lockscreen fails after STAGE_TMP already exists.
            lock.chmod(0o555)

            env = os.environ.copy()
            env.update(
                HOME=str(home),
                XDG_RUNTIME_DIR=str(runtime),
                RYOKU_QYLOCK_BUNDLE=str(bundle),
                RYOKU_QYLOCK_MODE="stage",
                RYOKU_QYLOCK_USER_ONLY="1",
                RYOKU_QYLOCK_GENERATION_GUARDED="1",
                RYOKU_QYLOCK_INLINE_GENERATION_GUARD="1",
            )

            proc = subprocess.run(
                ["bash", str(INSTALLER)],
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertNotEqual(proc.returncode, 0, proc.stdout + proc.stderr)

            stage_parent = home / ".local/share/ryoku"
            leftovers = list(stage_parent.glob("qylock-next.staging.*"))
            self.assertEqual(
                leftovers,
                [],
                "staging leftovers: "
                f"{leftovers}\nstdout:\n{proc.stdout}\nstderr:\n{proc.stderr}",
            )
            self.assertFalse((stage_parent / "qylock-next").exists())


if __name__ == "__main__":
    unittest.main()
