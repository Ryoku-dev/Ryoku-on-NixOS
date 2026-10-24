import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import Ryoku.Ui.Singletons

GridLayout {
    id: root

    property string source: "wallpaper"
    property int loadedCount: 0
    property real cellHeight: Tokens.rowH + Tokens.s5
    property string hoveredName: ""
    property bool showTooltips: true

    readonly property var colorSchemes: root.source === "themes"
        ? MaterialThemeLoader.namedThemes : MaterialThemeLoader.wallpaperSchemes

    implicitWidth: parent ? parent.width : 0
    columns: Math.max(2, Math.min(3,
        Math.floor(Math.max(1, width) / (Tokens.cellH - Tokens.s2))))
    columnSpacing: Tokens.s2
    rowSpacing: Tokens.s2

    function formatScheme(value) {
        const name = String(value).replace(/^scheme-/, "").replace(/-/g, " ");
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function restartLoad() {
        root.loadedCount = 0;
        loadTimer.restart();
    }

    onColorSchemesChanged: root.restartLoad()
    onSourceChanged: root.restartLoad()

    Repeater {
        model: root.colorSchemes

        delegate: ColorPreviewButton {
            required property int index
            required property var modelData
            Layout.fillWidth: true
            Layout.preferredHeight: root.cellHeight
            showTooltip: root.showTooltips

            themeCard: root.source === "themes" ? modelData : null
            colorScheme: root.source === "themes"
                ? "" : String(modelData)
            colorSchemeDisplayName: root.source === "themes"
                ? String(modelData?.label ?? modelData?.id ?? "")
                : root.formatScheme(modelData)
            shouldLoad: index < root.loadedCount

            onHoveredChanged: {
                if (hovered)
                    root.hoveredName = colorSchemeDisplayName;
                else if (root.hoveredName === colorSchemeDisplayName)
                    root.hoveredName = "";
            }
        }
    }

    Timer {
        id: loadTimer
        interval: Tokens.snap
        repeat: true
        onTriggered: {
            root.loadedCount = Math.min(root.colorSchemes.length,
                root.loadedCount + Math.max(1, Math.ceil(root.colorSchemes.length / 3)));
            if (root.loadedCount >= root.colorSchemes.length)
                stop();
        }
    }

    Component.onCompleted: root.restartLoad()
}
