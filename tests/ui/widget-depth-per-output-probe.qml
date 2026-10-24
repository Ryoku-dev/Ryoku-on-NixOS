import QtQuick
import Quickshell
import "modules/desktop/Singletons" as WidgetStore

ShellRoot {
    id: root

    property int failures: 0

    function closeTo(actual, expected) {
        return Math.abs(actual - expected) < 0.0001;
    }

    function check(name, ok) {
        console.log((ok ? "ok  " : "FAIL ") + name);
        if (!ok)
            failures++;
    }

    function run() {
        check("legacy depth is the first output fallback",
            closeTo(WidgetStore.Config.widgetDepth("clock", "DP-1"), 0.37));
        check("legacy depth is the second output fallback",
            closeTo(WidgetStore.Config.widgetDepth("clock", "HDMI-A-1"), 0.37));

        WidgetStore.Config.setWidgetDepth("DP-1", "clock", 0.2);
        WidgetStore.Config.setWidgetDepth("HDMI-A-1", "clock", 0.8);

        check("first output keeps its own depth",
            closeTo(WidgetStore.Config.widgetDepth("clock", "DP-1"), 0.2));
        check("second output keeps its own depth",
            closeTo(WidgetStore.Config.widgetDepth("clock", "HDMI-A-1"), 0.8));
        check("untouched output still falls back to legacy depth",
            closeTo(WidgetStore.Config.widgetDepth("clock", "eDP-1"), 0.37));
        check("legacy depth remains intact",
            closeTo(Number(WidgetStore.Config.widgetDepths.clock), 0.37));
        finish.restart();
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (!WidgetStore.Config.ready)
                return;
            stop();
            root.run();
        }
    }

    Timer {
        id: finish
        interval: 800
        onTriggered: {
            console.log(root.failures === 0
                ? "WIDGET-DEPTH-PER-OUTPUT-PROBE-PASS"
                : "WIDGET-DEPTH-PER-OUTPUT-PROBE-FAIL " + root.failures);
            Qt.exit(root.failures === 0 ? 0 : 1);
        }
    }
}
