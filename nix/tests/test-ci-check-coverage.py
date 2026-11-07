#!/usr/bin/env python3
"""CI must run the checks that guard install, update and session safety.

Several of these tests existed for a long time without any workflow building
them. This keeps the explicit lists in the workflows honest: every listed check
must exist, and the safety-critical ones must stay listed in both workflows.
"""
import os
import re
import unittest
from pathlib import Path

ROOT = Path(os.environ.get("RYOKU_CI_ROOT", Path(__file__).parents[2]))

# Failure scenarios whose regression tests must run in CI.
REQUIRED = {
    "ryoku-ci-check-coverage",
    "ryoku-installer-transaction",
    "ryoku-installer-iso",
    "ryoku-installer-disk-identity",
    "ryoku-install-parser",
    "ryoku-nix-update-lock",
    "ryoku-nix-update-local-rollback",
    "ryoku-nix-update-activation-rollback",
    "ryoku-nix-update-refresh",
    "ryoku-nix-update-interrupt",
    "ryoku-materialize-session",
    "ryoku-sddm-theme-apply",
    "ryoku-bridge-command-ownership",
    "ryoku-session-bootstrap",
    "ryoku-firstboot-session",
    "ryoku-firstboot-greeter-guard",
    "ryoku-firstboot-qml-imports",
}
# Checks a QML-only change must run; nix-iso.yml does not trigger on QML.
FIRSTBOOT = {
    "ryoku-firstboot-session",
    "ryoku-firstboot-greeter-guard",
    "ryoku-firstboot-qml-imports",
}
FIRSTBOOT_WORKFLOW = ".github/workflows/nix-firstboot.yml"
WORKFLOWS = [".github/workflows/nix-cache.yml", ".github/workflows/nix-iso.yml"]


def listed(text):
    return set(re.findall(r"checks\.x86_64-linux\.([A-Za-z0-9_-]+)", text))


class CiCoverageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        flake = (ROOT / "flake.nix").read_text()
        cls.defined = set(re.findall(r"^ {8}([A-Za-z0-9_-]+) =", flake, re.M))

    def test_required_checks_exist(self):
        self.assertFalse(REQUIRED - self.defined, REQUIRED - self.defined)

    def test_every_listed_check_exists(self):
        for path in WORKFLOWS + ["nix/sync/run-checks"]:
            with self.subTest(path=path):
                names = listed((ROOT / path).read_text())
                self.assertFalse(names - self.defined, names - self.defined)

    def test_required_checks_run_in_every_workflow(self):
        for path in WORKFLOWS + ["nix/sync/run-checks"]:
            with self.subTest(path=path):
                missing = REQUIRED - listed((ROOT / path).read_text())
                self.assertFalse(missing, f"{path} does not run {sorted(missing)}")

    def test_pull_request_filter_covers_updater_inputs(self):
        text = (ROOT / ".github/workflows/nix-iso.yml").read_text()
        for section in text.split("pull_request:", 1)[1].split("concurrency:", 1)[0:1]:
            for needed in ("nix/scripts/ryoku-nix-update", "nix/tests/test-nix-update-*",
                           "nix/scripts/ryoku-sddm-theme-apply", "nix/tests/test-ci-check-coverage.py",
                           "nix/modules/**", "nix/tests/firstboot-*", "nix/tests/test-firstboot-*",
                           "ryoku/lockscreen/sddm/ryoku-greeter-guard"):
                self.assertIn(needed, section)

    def test_qml_changes_run_firstboot_checks(self):
        text = (ROOT / FIRSTBOOT_WORKFLOW).read_text()
        self.assertFalse(FIRSTBOOT - listed(text), FIRSTBOOT - listed(text))
        self.assertFalse(listed(text) - self.defined, listed(text) - self.defined)
        section = text.split("pull_request:", 1)[1].split("concurrency:", 1)[0]
        for needed in ("'**/*.qml'", "'**/qmldir'", "nix/tests/test-firstboot-*"):
            self.assertIn(needed, section)


if __name__ == "__main__":
    unittest.main()
