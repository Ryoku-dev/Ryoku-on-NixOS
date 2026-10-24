#!/usr/bin/env python3
import os
from pathlib import Path
import unittest


MODULE = Path(
    os.environ.get(
        "RYOKU_QYLOCK_NIX_MODULE",
        Path(__file__).parents[1] / "modules" / "ryoku.nix",
    )
)


def pam_service(source, name):
    marker = "cat > " + f'"$pam_dir/{name}"' + " <<'EOF'\n"
    start = source.index(marker) + len(marker)
    end = source.index("\nEOF", start)
    return source[start:end]


class QylockPamMaterializationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = MODULE.read_text()

    def test_fingerprint_service_fails_closed(self):
        service = pam_service(self.source, "ryoku-lock")
        self.assertIn(
            "${qylockPamModules}/pam_deny.so",
            service,
        )
        self.assertIn("account    required", service)
        self.assertIn("session    required", service)

    def test_password_service_uses_ryoku_pam_modules(self):
        service = pam_service(self.source, "ryoku-lock-pw")
        self.assertIn(
            "auth       required  ${qylockPamModules}/pam_unix.so nullok",
            service,
        )
        self.assertIn(
            "account    required  ${qylockPamModules}/pam_unix.so",
            service,
        )
        self.assertIn(
            "password   required  ${qylockPamModules}/pam_deny.so",
            service,
        )
        self.assertIn(
            "session    required  ${qylockPamModules}/pam_unix.so",
            service,
        )

    def test_other_is_present_and_denies_each_stack(self):
        service = pam_service(self.source, "other")
        entries = {
            fields[0]: fields
            for line in service.splitlines()
            if (fields := line.split())
        }
        for stack in ("auth", "account", "password", "session"):
            self.assertEqual(entries[stack][1], "required")
            self.assertTrue(entries[stack][-1].endswith("pam_deny.so"))

    def test_every_pam_module_uses_ryoku_pam_modules(self):
        for name in ("ryoku-lock", "ryoku-lock-pw", "other"):
            with self.subTest(service=name):
                for line in pam_service(self.source, name).splitlines():
                    if ".so" in line:
                        self.assertIn(
                            "${qylockPamModules}/",
                            line,
                        )

    def test_pam_modules_come_from_ryoku_package_set(self):
        self.assertIn(
            'qylockPamModules = "${ryokuNixpkgs.linux-pam}/lib/security";',
            self.source,
        )
        self.assertNotIn("${config.security.pam.package}", self.source)

    def test_materializer_runs_before_lock_runtime_activation(self):
        start = self.source.index(
            "    systemd.user.services.ryoku-shell = {"
        )
        pre_start = self.source.index("        ExecStartPre = [", start)
        pre_end = self.source.index("        ];", pre_start)
        service_header = self.source[start:pre_start]
        commands = self.source[pre_start:pre_end]
        self.assertLess(
            commands.index("${qylockMaterializer}"),
            commands.index("ryoku-qylock-activate"),
        )
        self.assertIn("restartTriggers = [ qylockMaterializer ];", service_header)


if __name__ == "__main__":
    unittest.main(verbosity=2)
