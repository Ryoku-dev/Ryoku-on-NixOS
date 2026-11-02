#!/usr/bin/env python3
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

parser = argparse.ArgumentParser()
parser.add_argument("--runtime", required=True, type=Path)
args = parser.parse_args()
runtime = args.runtime / "share/quickshell/inir"


class ShimaAppearanceTests(unittest.TestCase):
    def source(self, path):
        source = runtime / path
        self.assertTrue(source.is_file(), f"Missing upstream component: {path}")
        return source.read_text()

    def test_ryoku_hub_is_available_inside_upstream_shell(self):
        actions = self.source("services/GlobalActions.qml")
        self.assertEqual(actions.count('id: "open-ryoku-hub"'), 1)
        self.assertIn('["ryoku-shell", "hub", "open"]', actions)

    def test_visualizers_share_upstream_cava_service(self):
        service = self.source("services/deferred/CavaService.qml")
        self.assertIn("function subscribe(", service)
        self.assertIn("function unsubscribe(", service)
        consumer = self.source("modules/common/widgets/CavaProcess.qml")
        self.assertIn("CavaService.subscribe(", consumer)
        self.assertIn("CavaService.unsubscribe(", consumer)
        self.assertIn("CavaProcess {", self.source("modules/iris/components/IrisVisualizer.qml"))
        self.assertIn("CavaProcess {", self.source("modules/iris/frame/IrisFramePulse.qml"))
        bar = self.source("modules/iris/bar/IrisBar.qml")
        self.assertIn("IrisFramePulse {", bar)
        self.assertIn("frameMusicLevel:", bar)
        self.assertIn("frameMusic", self.source("modules/iris/settings/IrisOptions.qml"))
        self.assertTrue((runtime / "modules/background/widgets/visualizer/VisualizerWidget.qml").is_file())

    def test_liquid_glass_and_frame_options_remain_available(self):
        themes = self.source("modules/iris/settings/IrisThemes.qml")
        self.assertIn('id: "liquid-glass"', themes)
        self.assertIn('"glass.mode": "wallpaper"', themes)
        options = self.source("modules/iris/settings/IrisOptions.qml")
        for key in ("iris.appearance.glass.mode", "iris.surround.music",
                    "iris.surround.musicStrength", "iris.surround.musicSensitivity",
                    "iris.surround.musicAppearance"):
            self.assertIn(key, options)

    def test_cava_config_uses_pipewire_monitor_and_respects_filter(self):
        original = runtime / "scripts/cava/generate_config.sh"
        self.assertTrue(original.is_file())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script = root / "cava/generate_config.sh"
            script.parent.mkdir()
            shutil.copy2(original, script)
            resolver = script.with_name("resolve_audio_source.py")
            resolver.write_text('print("test-sink.monitor")\n')
            bin_path = root / "bin"
            bin_path.mkdir()
            pactl = bin_path / "pactl"
            pactl.write_text('#!/bin/sh\ncase "$1" in info) printf "Server Name: PulseAudio (on PipeWire 1.0)\\n";; get-default-sink) echo test-sink;; esac\n')
            pactl.chmod(0o755)
            env = os.environ | {"PATH": str(bin_path) + os.pathsep + os.environ["PATH"]}
            out = root / "cava.conf"
            subprocess.run(["bash", str(script), str(out), "60", "120", "64", "true", "player", "[]"],
                           env=env, capture_output=True, text=True, check=True)
            config = out.read_text()
            for expected in ("method = pipewire", "source = test-sink.monitor",
                             "framerate = 60", "sensitivity = 120",
                             "bars = 64", "channels = stereo"):
                self.assertIn(expected, config)
            resolver.write_text('raise SystemExit(3)\n')
            blocked = root / "blocked.conf"
            proc = subprocess.run(["bash", str(script), str(blocked), "60", "100", "50", "false", "player", '["blocked"]'],
                                  env=env, capture_output=True, text=True)
            self.assertEqual(proc.returncode, 3)
            self.assertFalse(blocked.exists())


if __name__ == "__main__":
    unittest.main(argv=["test-shima-appearance"], verbosity=1)
