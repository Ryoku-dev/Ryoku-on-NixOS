#!/usr/bin/env python3
"""Compile two palette accents using the installed helper and read-only data.

No compositor, wallpaper or user cursor settings are touched. The Hyperion
helper's sizes argument also exercises the fast path's build.toml rewrite.
"""

import hashlib
import inspect
from pathlib import Path
import runpy
import shutil
import sys
import unittest
import zipfile


HELPER = Path(sys.argv.pop(1))


class CursorMaterialRuntimeTests(unittest.TestCase):
    def test_readonly_source_recolors_both_cursor_formats(self):
        helper = runpy.run_path(str(HELPER))
        source = helper["SRC"]
        config_files = [source / "config/render.json", source / "config/build.toml"]
        original = [(path.read_bytes(), path.stat().st_mode) for path in config_files]
        self.assertTrue(all(mode & 0o222 == 0 for _, mode in original))
        compile_theme = helper["compile_theme"]

        for flag, cursor in (("--hypr", "hyprcursors/left_ptr.hlc"),
                             ("--x11", "cursors/left_ptr")):
            digests = []
            for accent in ("#2255cc", "#ee9933"):
                with self.subTest(format=flag, accent=accent):
                    kwargs = {}
                    if flag == "--x11" and "sizes" in inspect.signature(compile_theme).parameters:
                        kwargs["sizes"] = [24]
                    work, compiled = compile_theme(
                        [flag], *helper["colors_from"](accent), **kwargs
                    )
                    try:
                        data = (compiled / cursor).read_bytes()
                        self.assertTrue(data)
                        if flag == "--hypr":
                            with zipfile.ZipFile(compiled / cursor) as archive:
                                data = archive.read("left_ptr.svg")
                            self.assertIn(accent.encode(), data.lower())
                        else:
                            # Xcursor stores little-endian ARGB pixels.
                            rgb = bytes.fromhex(accent[1:])
                            self.assertIn(bytes(reversed(rgb)) + b"\xff", data)
                        digests.append(hashlib.sha256(data).hexdigest())
                    finally:
                        # Do not ignore errors: copied store modes must not
                        # leave undeletable compilation trees in /tmp either.
                        shutil.rmtree(work)
                    self.assertFalse(work.exists())
            if len(digests) == 2:
                self.assertNotEqual(digests[0], digests[1], f"{flag} ignored the changed accent")

        self.assertEqual(
            [(path.read_bytes(), path.stat().st_mode) for path in config_files], original
        )


if __name__ == "__main__":
    unittest.main()
