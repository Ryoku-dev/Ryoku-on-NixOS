#!/usr/bin/env python3
import os
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


def source_path(env_name, relative):
    return Path(os.environ.get(env_name, ROOT / relative))


MODULE = source_path("RYOKU_NIX_MODULE", "nix/modules/ryoku.nix")
SHELL_QML = source_path("RYOKU_SHELL_QML", "ryoku/shell/quickshell/shell/shell.qml")
NOTIFS_QML = source_path("RYOKU_NOTIFS_QML", "ryoku/shell/quickshell/shell/services/Notifs.qml")
SCHEME_QML = source_path("RYOKU_SCHEME_QML", "ryoku/shell/quickshell/shell/services/Scheme.qml")
CARD_QML = source_path(
    "RYOKU_NOTIFICATION_CARD_QML",
    "ryoku/shell/quickshell/shell/modules/notifications/NotificationCard.qml",
)
IRIS_THEME_QML = source_path(
    "RYOKU_IRIS_THEME_QML",
    "ryoku/shell/quickshell/inir/services/MaterialThemeLoader.qml",
)


class NotificationOwnershipTest(unittest.TestCase):
    def test_shell_retires_stale_mako_before_start(self):
        text = MODULE.read_text()
        shell = text.split("systemd.user.services.ryoku-shell = {", 1)[1]
        shell = shell.split("\n    };\n  };", 1)[0]

        stop = '"-${pkgs.systemd}/bin/systemctl --user stop mako.service"'
        kill = '"-${pkgs.procps}/bin/pkill -f /bin/mako([[:space:]]|$)"'
        qylock = '"${ryokuHelpers}/bin/ryoku-qylock-activate"'

        self.assertIn(stop, shell)
        self.assertIn(kill, shell)
        self.assertIn(qylock, shell)
        self.assertLess(shell.index(stop), shell.index(qylock))
        self.assertLess(shell.index(kill), shell.index(qylock))

    def test_dnd_is_shared_shell_state(self):
        shell = SHELL_QML.read_text()
        notifs = NOTIFS_QML.read_text()

        binding = """
    Binding {
        target: Notifs
        property: "dnd"
        value: Flags.dnd
    }
"""
        self.assertIn(binding, shell)
        self.assertIn("property bool dnd: false", notifs)
        self.assertIn("if (!root.dnd)", notifs)

    def test_notifications_follow_the_live_wallpaper_palette(self):
        scheme = SCHEME_QML.read_text()
        card = CARD_QML.read_text()
        iris = IRIS_THEME_QML.read_text()

        self.assertIn('/ryoku/colors.json"', scheme)
        self.assertIn("watchChanges: true", scheme)
        self.assertIn('color: card.unifiedFrame ? "transparent" : Theme.surface', card)
        self.assertIn("border.color: Theme.outline", card)
        self.assertIn("Directories.generatedMaterialThemePath", iris)
        self.assertIn("watchChanges: true", iris)


if __name__ == "__main__":
    unittest.main()
