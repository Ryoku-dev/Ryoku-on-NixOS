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

    def test_ryoku_frontend_is_orthogonal_to_liquid_glass(self):
        options = self.source("modules/iris/settings/IrisOptions.qml")
        themes = self.source("modules/iris/settings/IrisThemes.qml")
        style = self.source("modules/iris/style/IrisStyle.qml")
        tokens = self.source("services/RyokuTokens.qml")
        self.assertIn('path: "iris.appearance.frontend"', options)
        self.assertIn('value:"ryoku"', options)
        self.assertIn('value:"inir"', options)
        self.assertIn('"iris.appearance.frontend"', themes)
        self.assertIn('RyokuTokens.paper', style)
        self.assertIn('RyokuTokens.ink', style)
        self.assertIn('RyokuTokens.bone', style)
        self.assertIn('/.cache/ryoku/colors.json', tokens)
        self.assertNotIn('XDG_CACHE_HOME") ||', tokens)
        self.assertIn('singleton RyokuTokens 1.0', self.source("services/qmldir"))

    def test_theme_card_selects_persisted_ryoku_frontend(self):
        schema = self.source("modules/common/Config.qml")
        themes = self.source("modules/iris/settings/IrisThemes.qml")
        card = self.source("modules/iris/edit/IrisThemeCard.qml")
        bar = self.source("modules/iris/bar/IrisBar.qml")
        self.assertIn('property string frontend: "inir"', schema)
        self.assertIn('if (theme.id === "ryoku")', themes)
        self.assertIn('Config.setNestedValue("iris.appearance.frontend", "ryoku")', themes)
        self.assertIn('card.theme.id === "ryoku"', card)
        self.assertIn('IrisStyle.ryokuFrontend', card)
        self.assertIn('IrisThemes.choose(found)', bar)
        self.assertIn('ryoku ? RyokuTokens.paper', themes)

    def test_wave_and_frame_colour_editors(self):
        options = self.source("modules/iris/settings/IrisOptions.qml")
        schema = self.source("modules/common/Config.qml")
        frame = self.source("modules/iris/frame/IrisFrame.qml")
        for key in (
            "background.edgeWidgets.organic.palette",
            "background.edgeWidgets.organic.colorMode",
            "background.edgeWidgets.organic.primaryColor",
            "background.edgeWidgets.organic.secondaryColor",
            "background.edgeWidgets.organic.tertiaryColor",
            "iris.surround.musicCustomColour",
        ):
            self.assertIn('path: "' + key + '"', options)
        self.assertIn("choices: EdgeConfig.palettes.map", options)
        self.assertIn('Open Organic Edge colours', options)
        self.assertIn('property string musicCustomColour: "#e6e1da"', schema)
        self.assertIn('colour === "custom"', frame)
        self.assertIn('root.surround?.musicCustomColour', frame)

    def test_frame_and_full_spectrum_edge_wave_can_coexist(self):
        options = self.source("modules/iris/settings/IrisOptions.qml")
        frame = self.source("modules/iris/frame/IrisFrame.qml")
        pulse = self.source("modules/iris/frame/IrisFramePulse.qml")
        edge = self.source("modules/background/widgets/OrganicEdgeWidget.qml")
        self.assertIn('value:"both"', options)
        self.assertIn('path: "background.edgeWidgets.organic.edges"', options)
        self.assertIn('["frame", "both"].includes', frame)
        self.assertIn('=== "frame"', edge)
        self.assertNotIn('MprisController.activePlayer?.isPlaying', pulse)
        for band in ('lowLevel', 'midLevel', 'highLevel'):
            self.assertIn(band, pulse)
        self.assertIn('running: root.active && (cava.audioSignalActive', pulse)

    def test_shima_family_actions_are_accessible(self):
        menu = self.source("modules/iris/background/IrisDesktopActions.qml")
        for family in ("iris", "ii", "waffle"):
            self.assertIn('"panelFamily", "set", "' + family + '"', menu)
        self.assertIn('id: "shimaAppearance"', menu)

    def test_liquid_glass_and_frame_options_remain_available(self):
        themes = self.source("modules/iris/settings/IrisThemes.qml")
        self.assertIn('id: "liquid-glass"', themes)
        self.assertIn('"glass.mode": "wallpaper"', themes)
        options = self.source("modules/iris/settings/IrisOptions.qml")
        for key in ("iris.appearance.glass.mode", "iris.surround.music",
                    "iris.surround.musicStrength", "iris.surround.musicSensitivity",
                    "iris.surround.musicAppearance"):
            self.assertIn(key, options)

    def test_ryoku_desktop_actions(self):
        menu = self.source("modules/iris/background/IrisDesktopActions.qml")
        for section in ("subshells", "bar-studio", "desktop"):
            self.assertIn('["ryoku-shell", "hub", "open", "' + section + '"]', menu)
        self.assertIn('["ryoku-shell", "hub", "open"]', menu)
        self.assertIn('id: "ryokuSubshells"', menu)

    def test_widget_canvas_and_lightweight_desktop_are_accessible(self):
        critical = self.source("modules/iris/critical/ShellIrisCriticalPanels.qml")
        deferred = self.source("modules/iris/ShellIrisPanelsImpl.qml")
        self.assertIn('component: IrisBackground {}', critical)
        self.assertNotIn('identifier: "irisBackground"', critical)
        self.assertIn('component: Background {}', deferred)
        self.assertNotIn('includes("irisBackground")', deferred)
        self.assertIn('iris?.modules?.desktopWidgets ?? true', critical)
        self.assertIn('iris?.modules?.desktopWidgets ?? true', deferred)

    def test_ryoku_theme_preset_preserves_upstream_themes(self):
        themes = self.source("modules/iris/settings/IrisThemes.qml")
        self.assertEqual(themes.count('id: "ryoku", name: "Ryoku"'), 1)
        self.assertIn('"iris.appearance.scheme": "ink"', themes)
        self.assertIn('id: "liquid-glass"', themes)
        self.assertIn('id: "iris", name: "iRiS"', themes)

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
