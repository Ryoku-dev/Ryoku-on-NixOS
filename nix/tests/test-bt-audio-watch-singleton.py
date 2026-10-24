#!/usr/bin/env python3
import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest


HELPER = pathlib.Path(
    os.environ.get(
        "RYOKU_BT_AUDIO_TEST_HELPER",
        pathlib.Path(__file__).parents[2] / "system/hardware/audio/ryoku-bt-audio",
    )
)


class BluetoothAudioWatchTest(unittest.TestCase):
    def test_only_one_watcher_owns_runtime_lock(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            runtime = root / "runtime"
            config = root / "bluetooth.json"
            marker = root / "subscribed"
            fake = root / "pactl"
            runtime.mkdir()

            fake.write_text(
                f"#!{sys.executable}\n"
                "import os\n"
                "import sys\n"
                "import time\n"
                "args = sys.argv[1:]\n"
                "if args == ['subscribe']:\n"
                "    open(os.environ['RYOKU_BT_TEST_MARKER'], 'w').close()\n"
                "    time.sleep(30)\n"
                "elif args == ['list', 'cards', 'short']:\n"
                "    pass\n"
            )
            fake.chmod(0o755)

            env = os.environ.copy()
            env.update(
                XDG_RUNTIME_DIR=str(runtime),
                RYOKU_BT_CONFIG=str(config),
                RYOKU_BT_PACTL=str(fake),
                RYOKU_BT_TEST_MARKER=str(marker),
            )

            first = subprocess.Popen(
                ["bash", str(HELPER), "watch"],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
            )
            try:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline and not marker.exists():
                    time.sleep(0.02)
                self.assertTrue(marker.exists(), "first watcher never subscribed")
                self.assertIsNone(first.poll(), "first watcher exited unexpectedly")

                second = subprocess.run(
                    ["bash", str(HELPER), "watch"],
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=2,
                )
                self.assertEqual(second.returncode, 0, second.stderr)
                self.assertIsNone(first.poll(), "second watcher displaced the owner")
            finally:
                first.terminate()
                try:
                    first.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    first.kill()
                    first.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
