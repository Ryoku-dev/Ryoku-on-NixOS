import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Widgets
import stage.modules.common
import stage.modules.common.widgets
import stage.services
import "./widgets"
import "."

Item {
    id: root

    property bool isVertical: false
    property var dockContent: null
    property int delegateIndex: -1

    readonly property real buttonSize: Appearance.sizes.dockButtonSize
    readonly property real dotMargin: root.dockContent?.dotMargin ?? Math.max(1, Math.round((Config.options?.dock.height ?? 60) * 0.2) - 2)
    readonly property real dotMarginV: root.dockContent?.dotMarginV ?? root.dotMargin
    readonly property real slotSize: root.dockContent?.buttonSlotSize ?? (buttonSize + dotMargin * 2)
    readonly property real slotHeight: root.dockContent
        ? (root.isVertical ? root.dockContent.buttonSlotSize : root.dockContent.buttonSlotHeight)
        : (buttonSize + dotMarginV * 2)
    readonly property real fixedSlots: isVertical ? 2.5 : 3
    readonly property real fixedLength: fixedSlots * slotSize

    implicitWidth: root.isVertical ? root.slotSize : root.fixedLength
    implicitHeight: root.isVertical ? root.slotSize : root.slotHeight
    // Magnified with the icons, at the muted share the dock keeps for a widget
    // body: the delegate wrapper grows the slot by exactly the room this scale
    // needs, so the neighbours slide instead of being drawn over.
    readonly property real contentMagnification: root.dockContent ? root.dockContent._getSlotMagScale(root) : 1.0
    scale: root.contentMagnification
    transformOrigin: root.dockContent?.magnificationTransformOrigin ?? Item.Bottom

    // ── Drag overlay (reorder support) ─────────────────────────────────────
    MouseArea {
        id: dragOverlay
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property real pressCoord: 0
        property bool dragActive: false

        onEntered: {
            root.weatherHovered = true;
            if (root.dockContent)
                root.dockContent.onButtonEntered(root);
        }
        onExited: {
            root.weatherHovered = false;
            if (root.dockContent)
                root.dockContent.onButtonExited(root);
        }

        onPressed: (event) => {
            if (event.button === Qt.LeftButton) {
                pressCoord = root.isVertical ? event.y : event.x
            }
        }
        onPositionChanged: (event) => {
            if (!pressed) return
            var cur = root.isVertical ? event.y : event.x
            var dist = Math.abs(cur - pressCoord)
            if (!dragActive && dist > 5 && root.delegateIndex >= 0) {
                dragActive = true
                if (root.dockContent) {
                    root.dockContent.startItemDrag(root.delegateIndex, dragOverlay, event.x, event.y)
                }
            }
            if (dragActive) {
                if (root.dockContent) root.dockContent.moveItemDrag(dragOverlay, event.x, event.y)
            }
        }
        onReleased: (event) => {
            if (dragActive) {
                dragActive = false
                if (root.dockContent) root.dockContent.endItemDrag()
                return
            }
            if (event.button === Qt.LeftButton) {
                if (weatherMenu.active && !weatherMenu.isClosing)
                    weatherMenu.close()
                else
                    weatherMenu.open()
            }
        }
        onCanceled: {
            if (dragActive) {
                dragActive = false
                if (root.dockContent) root.dockContent.cancelDrag()
            }
        }
    }

    DockTooltip {
        id: weatherTooltip
        parentItem: root
        text: root.weatherDesc + " · " + root.cityName
        showTooltip: dragOverlay.containsMouse && !weatherMenu.active
        tooltipOffset: -root.dotMargin
    }

    property bool weatherHovered: false

    readonly property string cityName: Weather.data?.city || Translation.tr("Unknown")
    readonly property string weatherDesc: Translation.tr(Weather.data?.wDesc || "Unknown")
    readonly property string temperature: (Weather.data?.temp || "--").replace(/[^-0-9]/g, "") + "°"

    function get3DWeatherIconName(wCode) {
        let iconName = Icons.getWeatherIcon(wCode);
        if(!iconName) return "clouds.png";
        switch(iconName) {
            case "clear_day": return "sun.png";
            case "partly_cloudy_day": return "sun-clouds.png";
            case "cloud":
            case "foggy": return "clouds.png";
            case "rainy":
            case "weather_hail": return "sun-clouds-rain.png";
            case "thunderstorm": return "lightning.png";
            case "cloudy_snowing":
            case "snowing_heavy":
            case "snowing": return "clouds-snow.png";
            default: return "clouds.png";
        }
    }

    readonly property string iconFileName: get3DWeatherIconName(Weather.data?.wCode)
    readonly property bool isSunny: iconFileName === "sun.png" || iconFileName === "sun-clouds.png"
    readonly property bool isNight: Weather.data?.isDay === false

    function getGradientColor(position) {
        if (root.isSunny) {
            if (root.isNight) {
                return position === 0 ? "#1a2a44" : "#0d1526"; // Dark Night Blue
            }
            return position === 0 ? "#2e8fd3" : "#2764b1"; // Day Blue
        } else {
            if (root.isNight) {
                return position === 0 ? "#37474f" : "#263238"; // Dark Grey
            }
            return position === 0 ? "#a1a1a1" : "#6b6b6b"; // Day Grey
        }
    }

    function materialWeatherSymbol(code, day) {
        const value = Number(code);
        if (value === 0)
            return day ? "clear_day" : "clear_night";
        if (value === 1 || value === 2)
            return day ? "partly_cloudy_day" : "partly_cloudy_night";
        if (value === 3)
            return "cloud";
        if (value === 45 || value === 48)
            return "foggy";
        if (value >= 95)
            return "thunderstorm";
        if ((value >= 71 && value <= 77) || value === 85 || value === 86)
            return "weather_snowy";
        if ((value >= 51 && value <= 67) || (value >= 80 && value <= 82))
            return "rainy";
        return "cloud";
    }

    Component {
        id: weatherHeaderIcon
        Image {
            source: "file://" + Directories.assetsPath + "/icons/weather/" + root.iconFileName
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(width * 2, height * 2)
            smooth: true
        }
    }

    DockContextMenuBase {
        id: weatherMenu
        anchorItem: root
        geometryItem: bgRect
        menuWidth: 380
        headerText: root.weatherDesc
        headerSubtitle: root.cityName + " · " + (Weather.data?.temp || "--")
        headerIcon: weatherHeaderIcon
        contentComponent: Component {
            ColumnLayout {
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    visible: Weather.status === "loading" || Weather.status === "error"

                    MaterialSymbol {
                        text: Weather.status === "error" ? "cloud_off" : "progress_activity"
                        iconSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Weather.status === "error"
                            ? (Weather.errorText || Translation.tr("Error loading weather."))
                            : Translation.tr("Weather loading…")
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnSurfaceVariant
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    RippleButton {
                        visible: Weather.status === "error"
                        implicitWidth: 72
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        buttonText: Translation.tr("Retry")
                        onClicked: Weather.retry()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: Weather.available
                    spacing: 10

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: Weather.current?.temperature ?? "--"
                            color: Appearance.colors.colOnSurface
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr(Weather.current?.condition ?? root.weatherDesc)
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    Repeater {
                        model: [
                            { "unit": "celsius", "label": "°C" },
                            { "unit": "fahrenheit", "label": "°F" }
                        ]
                        delegate: RippleButton {
                            required property var modelData
                            implicitWidth: 44
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            buttonText: modelData.label
                            toggled: Weather.activeUnit === modelData.unit
                            onClicked: if (!toggled) Weather.setUnit(modelData.unit)
                        }
                    }
                    RippleButton {
                        implicitWidth: 34
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnSurface
                        }
                        onClicked: Weather.retry()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: Weather.available
                    spacing: 6

                    Repeater {
                        model: (Weather.hourly ?? []).slice(0, 5)
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 76
                            radius: Appearance.rounding.small
                            color: Appearance.colors.colLayer2

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 2
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.time ?? ""
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    elide: Text.ElideRight
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.materialWeatherSymbol(modelData.code, modelData.isDay)
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer2
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: modelData.temperature ?? ((modelData.temp ?? "--") + "°")
                                    horizontalAlignment: Text.AlignHCenter
                                    color: Appearance.colors.colOnLayer2
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: Weather.available
                    spacing: 4

                    Repeater {
                        model: (Weather.daily ?? []).slice(0, 3)
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            StyledText {
                                Layout.preferredWidth: 92
                                text: Translation.tr(modelData.weekday ?? modelData.day ?? "")
                                color: Appearance.colors.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            MaterialSymbol {
                                text: root.materialWeatherSymbol(modelData.code, true)
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: (modelData.high ?? ((modelData.hi ?? "--") + "°"))
                                    + "  " + (modelData.low ?? ((modelData.lo ?? "--") + "°"))
                                color: Appearance.colors.colOnSurfaceVariant
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: Weather.available
                    implicitHeight: metricsRow.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2

                    RowLayout {
                        id: metricsRow
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 8

                        Repeater {
                            model: [
                                {
                                    "icon": "thermostat",
                                    "label": Translation.tr("Feels"),
                                    "value": Weather.current?.feelsLike ?? "--"
                                },
                                {
                                    "icon": "humidity_percentage",
                                    "label": Translation.tr("Humidity"),
                                    "value": (Weather.current?.humidity ?? "--") + "%"
                                },
                                {
                                    "icon": "air",
                                    "label": Translation.tr("Wind"),
                                    "value": Weather.current
                                        ? (Weather.current.wind + " " + Weather.current.windUnits)
                                        : "--"
                                }
                            ]
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4
                                MaterialSymbol {
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: Appearance.colors.colOnLayer2
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.label
                                        color: Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: modelData.value
                                        color: Appearance.colors.colOnLayer2
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Weather.available && Weather.updatedAt.length > 0
                    text: Translation.tr("Updated %1").arg(Weather.updatedAt)
                    horizontalAlignment: Text.AlignRight
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    Connections {
        target: weatherMenu
        function onActiveChanged() {
            if (!root.dockContent)
                return
            if (weatherMenu.active)
                root.dockContent.registerContextMenuOpen()
            else
                root.dockContent.registerContextMenuClose()
        }
    }

    Component.onDestruction: {
        if (root.dockContent && weatherMenu.active)
            root.dockContent.registerContextMenuClose()
    }

    Rectangle {
        id: bgRect
        anchors.fill: parent
        anchors.leftMargin: root.dotMargin
        anchors.rightMargin: root.dotMargin
        anchors.topMargin: root.dotMarginV
        anchors.bottomMargin: root.dotMarginV
        radius: (Config.options?.dock?.widgetRadius ?? -1) >= 0 ? Config.options.dock.widgetRadius : (Appearance.rounding.windowRounding + 12)
        clip: true

        // Ensure children like the weather icon are properly clipped by the radius
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: bgRect.width
                height: bgRect.height
                radius: bgRect.radius
            }
        }

        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: getGradientColor(0) }
            GradientStop { position: 1.0; color: getGradientColor(1) }
        }

        Loader {
            active: !root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent

                ColumnLayout {
                    id: infoColumn
                    anchors.left: parent.left
                    anchors.leftMargin: root.dotMargin + 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    // Constrain width to leave room for temperature + icon
                    width: Math.max(1, root.fixedLength - root.buttonSize * 1.5 - root.dotMargin * 3 - 8)
                    clip: true

                    StyledText {
                        Layout.fillWidth: true
                        text: root.weatherDesc
                        font.pixelSize: Math.round(root.buttonSize * 0.28)
                        font.weight: Font.DemiBold
                        color: "white"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.cityName
                        font.pixelSize: Math.round(root.buttonSize * 0.24)
                        font.weight: Font.Normal
                        color: "white"
                        opacity: 0.8
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    anchors.right: parent.right
                    anchors.rightMargin: iconImg.width * 0.6
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.temperature
                    font.pixelSize: Math.round(root.buttonSize * 0.6)
                    font.weight: Font.Light
                    color: "white"
                }

                // Weather icon hover interaction: sits further right, slides left on hover
                readonly property real _weatherIconWidth: root.buttonSize * 1.3
                readonly property real _weatherIconBaseMargin: -(_weatherIconWidth * 0.25 + 6)
                readonly property real _weatherIconHoverMargin: _weatherIconBaseMargin + 6

                Image {
                    id: iconImg
                    source: "file://" + Directories.assetsPath + "/icons/weather/" + root.iconFileName
                    width: parent._weatherIconWidth
                    height: parent._weatherIconWidth
                    anchors.right: parent.right
                    anchors.rightMargin: root.weatherHovered ? parent._weatherIconHoverMargin : parent._weatherIconBaseMargin
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: height * 0.25
                    sourceSize: Qt.size(width * 2, height * 2)
                    smooth: true
                    antialiasing: true

                    Behavior on anchors.rightMargin {
                        enabled: !Appearance.reducedMotion
                        NumberAnimation {
                            duration: 700
                            easing.type: Easing.InOutCubic
                        }
                    }
                }
            }
        }

        Loader {
            active: root.isVertical
            anchors.fill: parent
            sourceComponent: Item {
                anchors.fill: parent
                StyledText {
                    anchors.centerIn: parent
                    text: root.temperature
                    font.pixelSize: Math.round(root.buttonSize * 0.45)
                    font.weight: Font.Bold
                    color: "white"
                }
            }
        }
    }
}
