import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

source = Path(__file__).parents[1] / "packages/shima/launcher.py"
spec = importlib.util.spec_from_file_location("shima_launcher", source)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)

class ShimaStateTests(unittest.TestCase):
    def test_first_launch_uses_iris_and_private_paths(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            config, state, cache = launcher.prepare(root/"config", root/"state", root/"cache")
            self.assertEqual(json.loads((config/"config.json").read_text())["panelFamily"], "iris")
            self.assertEqual(state, root/"state/ryoku/shima")
            self.assertEqual(cache, root/"cache/ryoku/shima")

    def test_relaunch_keeps_family_and_user_settings(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            config, _, _ = launcher.prepare(root/"config", root/"state", root/"cache")
            value = {"panelFamily":"waffle", "keep":42}
            (config/"config.json").write_text(json.dumps(value))
            launcher.prepare(root/"config", root/"state", root/"cache")
            self.assertEqual(json.loads((config/"config.json").read_text()), value)

    def test_legacy_settings_are_copied_without_modifying_shell(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            legacy = root/"config/ryoku/shell.json"
            legacy.parent.mkdir(parents=True)
            original = '{"barStyle":"iris","keep":7,"inir":{"iris":{"keep":42}}}'
            legacy.write_text(original)
            config, _, _ = launcher.prepare(root/"config", root/"state", root/"cache")
            self.assertEqual(json.loads((config/"config.json").read_text())["iris"]["keep"],42)
            self.assertEqual(legacy.read_text(), original)

    def test_managed_config_symlink_is_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            config,_,_=launcher.prepare(root/"config",root/"state",root/"cache")
            file=config/"config.json"
            file.unlink()
            target=root/"managed.json"
            target.write_text('{"keep":true}')
            file.symlink_to(target)
            with self.assertRaises(RuntimeError):
                launcher.prepare(root/"config",root/"state",root/"cache")
            self.assertTrue(file.is_symlink())
            self.assertEqual(target.read_text(),'{"keep":true}')

if __name__ == "__main__":
    unittest.main()
