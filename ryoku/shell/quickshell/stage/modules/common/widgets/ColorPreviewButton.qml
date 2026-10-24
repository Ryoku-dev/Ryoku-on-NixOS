import QtQuick
import QtQuick.Layouts
import stage.services
import stage.modules.common
import stage.modules.common.widgets
import Ryoku.Ui.Singletons

RippleButton {
    id: root

    property string colorScheme: "scheme-tonal-spot"
    property string colorSchemeDisplayName: ""
    property var themeCard: null
    property bool shouldLoad: false
    property bool showTooltip: true

    readonly property bool namedTheme: root.themeCard !== null
    readonly property string themeId: root.namedTheme
        ? String(root.themeCard.id ?? "") : ""
    readonly property var themeSwatches: root.namedTheme && Array.isArray(root.themeCard.sw)
        ? root.themeCard.sw : []
    readonly property bool toggled: root.namedTheme
        ? MaterialThemeLoader.themeName === root.themeId
        : MaterialThemeLoader.followsWallpaper
            && MaterialThemeLoader.schemeType === root.colorScheme

    property color primaryColor: "transparent"
    property color secondaryColor: "transparent"
    property color tertiaryColor: "transparent"
    property bool loaded: false
    property bool _cacheHeld: false

    Layout.fillWidth: true
    implicitHeight: Tokens.rowH + Tokens.s5
    enabled: !MaterialThemeLoader.busy
    opacity: enabled ? 1 : 0.55
    buttonRadius: Tokens.radius
    borderWidth: Tokens.border
    colBackground: root.toggled ? Tokens.bone : Tokens.paperLift
    colBackgroundHover: root.toggled ? Tokens.bone : Tokens.tint10
    colBackgroundActive: root.toggled ? Tokens.bone : Tokens.tint16
    colRipple: root.toggled ? Tokens.lineOnBone : Tokens.tint16
    borderColor: root.toggled ? Tokens.bone : Tokens.line
    scale: down ? 0.98 : 1

    Behavior on opacity {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.snap }
    }
    Behavior on scale {
        enabled: !Tokens.reduceMotion
        NumberAnimation { duration: Tokens.snap }
    }

    function releasePreviewCache() {
        if (!root._cacheHeld)
            return;
        root._cacheHeld = false;
        ThemePreviewCache.relinquish();
    }

    function applySwatch(swatch) {
        if (!swatch)
            return false;
        root.primaryColor = swatch.primary || "transparent";
        root.secondaryColor = swatch.secondary || "transparent";
        root.tertiaryColor = swatch.tertiary || "transparent";
        root.loaded = true;
        swatchCanvas.requestPaint();
        return true;
    }

    function loadNamedTheme() {
        if (!root.namedTheme)
            return;
        if (root.themeSwatches.length >= 5) {
            root.applySwatch({
                primary: root.themeSwatches[2],
                secondary: root.themeSwatches[3],
                tertiary: root.themeSwatches[4]
            });
        } else {
            root.loaded = false;
        }
    }

    function loadWallpaperScheme() {
        if (root.namedTheme || !root.shouldLoad)
            return;
        if (!root._cacheHeld) {
            root._cacheHeld = true;
            ThemePreviewCache.acquire();
        }
        root.applySwatch(ThemePreviewCache.wallpaperPreview(root.colorScheme));
    }

    onClicked: {
        if (root.namedTheme)
            MaterialThemeLoader.setTheme(root.themeId);
        else
            MaterialThemeLoader.setSchemeType(root.colorScheme);
    }

    onThemeCardChanged: {
        root.loaded = false;
        if (root.namedTheme) {
            root.releasePreviewCache();
            root.loadNamedTheme();
        } else {
            root.loadWallpaperScheme();
        }
    }
    onColorSchemeChanged: {
        if (!root.namedTheme) {
            root.loaded = false;
            root.loadWallpaperScheme();
        }
    }
    onShouldLoadChanged: {
        if (root.shouldLoad)
            root.namedTheme ? root.loadNamedTheme() : root.loadWallpaperScheme();
        else
            root.releasePreviewCache();
    }
    Component.onCompleted: {
        if (root.shouldLoad)
            root.namedTheme ? root.loadNamedTheme() : root.loadWallpaperScheme();
    }
    Component.onDestruction: root.releasePreviewCache()

    Connections {
        target: root._cacheHeld ? ThemePreviewCache : null
        function onWallpaperPreviewsChanged() {
            root.applySwatch(ThemePreviewCache.wallpaperPreview(root.colorScheme));
        }
        function onWallpaperPreviewsGenerationFailed() {
            root.loaded = false;
        }
    }

    StyledToolTip {
        extraVisibleCondition: root.showTooltip
        text: root.colorSchemeDisplayName
    }

    Item {
        anchors.fill: parent
        anchors.margins: Tokens.s2

        Rectangle {
            id: selectionRing
            anchors.centerIn: swatchCanvas
            width: swatchCanvas.width + Tokens.s1 * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Tokens.border * 2
            border.color: root.toggled ? Tokens.inkOnBone : Tokens.ink
            opacity: root.toggled && root.loaded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                enabled: !Tokens.reduceMotion
                NumberAnimation { duration: Tokens.snap }
            }
        }

        Canvas {
            id: swatchCanvas
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            readonly property real side: Math.max(Tokens.s5,
                Math.min(parent.width - Tokens.s4, parent.height - Tokens.s5))
            width: side
            height: side
            visible: root.loaded
            antialiasing: true
            onWidthChanged: requestPaint()
            onAvailableChanged: if (available) requestPaint()
            onVisibleChanged: if (visible) requestPaint()

            onPaint: {
                const context = getContext("2d");
                const center = width / 2;
                context.reset();

                context.beginPath();
                context.fillStyle = root.primaryColor;
                context.moveTo(center, center);
                context.arc(center, center, center, Math.PI, 0, false);
                context.fill();

                context.beginPath();
                context.fillStyle = root.secondaryColor;
                context.moveTo(center, center);
                context.arc(center, center, center, 0, Math.PI / 2, false);
                context.fill();

                context.beginPath();
                context.fillStyle = root.tertiaryColor;
                context.moveTo(center, center);
                context.arc(center, center, center, Math.PI / 2, Math.PI, false);
                context.fill();
            }
        }

        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            width: Tokens.ctlH
            height: Tokens.ctlH
            visible: !root.loaded
            text: root.namedTheme ? "palette" : "hourglass_top"
            iconSize: Tokens.s4
            color: root.toggled ? Tokens.inkOnBone : Tokens.inkMuted
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        StyledText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Tokens.fSmall + Tokens.s1
            text: root.colorSchemeDisplayName
            color: root.toggled ? Tokens.inkOnBone : Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fTiny
            font.weight: root.toggled ? Font.DemiBold : Font.Medium
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }
}
