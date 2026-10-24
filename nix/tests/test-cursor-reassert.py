import runpy
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


class CursorReassertTest(unittest.TestCase):
    def test_recolor_reasserts_the_configured_cursor(self):
        root = Path(__file__).resolve().parents[2]
        script = root / "release/packages/ryoku-cursor-material/ryoku-cursor-material-recolor"
        recolor = runpy.run_path(str(script))
        with patch("subprocess.run") as run:
            recolor["apply_live"]()
        run.assert_called_once_with(
            ["ryoku", "wm", "act", "cursor.reassert"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def test_background_xcursor_pass_reasserts_after_install(self):
        root = Path(__file__).resolve().parents[2]
        script = root / "release/packages/ryoku-cursor-material/ryoku-cursor-material-recolor"
        recolor = runpy.run_path(str(script))
        events = []

        globals_ = recolor["main"].__globals__
        overrides = {
            "accent": lambda: "#123456",
            "colors_from": lambda _accent: ("#111111", "#123456", "#222222"),
            "build_x11": lambda *_args: events.append("build-xcursor"),
            "apply_live": lambda: events.append("reassert"),
            "x11_locked": lambda fn: fn(),
        }
        with patch.dict(globals_, overrides), patch("sys.argv", [str(script), "--x11only"]):
            recolor["main"]()

        self.assertEqual(events, ["build-xcursor", "reassert"])


if __name__ == "__main__":
    unittest.main()
