#!/usr/bin/env python3

import io
import json
import os
import tempfile
import unittest
import urllib.error
from unittest import mock

import sync


class CopyDetectionTest(unittest.TestCase):
    def test_leading_placeholder_sentence_is_copy(self):
        self.assertTrue(sync._copy("%d orphaned package(s)"))
        self.assertTrue(sync._copy("%s is unavailable: %s"))

    def test_bare_placeholder_is_not_copy(self):
        self.assertFalse(sync._copy("%s"))
        self.assertFalse(sync._copy("%02d"))


class LLMUnavailableTest(unittest.TestCase):
    def test_cmd_sync_returns_three_without_writing_catalog(self):
        lang = next(iter(sync.TARGETS))
        with tempfile.TemporaryDirectory() as trans:
            with open(os.path.join(trans, "en.json"), "w", encoding="utf-8") as fh:
                json.dump({"Power limit": "Power limit"}, fh)

            error = urllib.error.HTTPError(
                "https://example.invalid", 402, "Payment Required", {},
                io.BytesIO(b"insufficient credits"))
            stderr = io.StringIO()
            with mock.patch.object(sync, "TRANS", trans), \
                    mock.patch.object(sync, "OVERRIDES", os.path.join(trans, "overrides")), \
                    mock.patch.object(sync, "load_llm_cfg", return_value={"key": "test"}), \
                    mock.patch.object(sync.urllib.request, "urlopen", side_effect=error), \
                    mock.patch("sys.stderr", stderr):
                result = sync.cmd_sync(["--engine", "llm", lang])

            self.assertEqual(result, 3)
            self.assertFalse(os.path.exists(os.path.join(trans, f"{lang}.json")))
            self.assertIn("translation provider unavailable: HTTP 402", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
