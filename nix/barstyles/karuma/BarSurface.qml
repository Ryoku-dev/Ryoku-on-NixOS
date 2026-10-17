pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.PluginKit
import "KarumaData.js" as HD
import "Title.js" as TitleJs
import "KarumaSchema.js" as Schema

/*
 * Everything drawn inside one Karuma bar strip. Pure QtQuick: plain data in,
 * signals out (Scene.qml feeds it live Ryoku data).
 *
 * Layout follows the original paper-and-ink "Ma" design, adapted for Karuma: the seal
 * (the hub button) remains the fixed brand anchor, while every other module is
 * placed from three explicit left / centre / right lanes. Built-ins and plugins
 * share the same layout model, and the clock is movable like any other module.
 * The shipped layout is:
 *   left    seal 力, kanji workspaces with a sliding plate, window byline
 *   centre  stacked serif clock with the day and date beside it
 *   right   media (the underline is the progress bar), 波 双 耳 光 充 readings
 *           held apart by space, indicator stamps, notification stamps
 *   edge    the rod under the strip, in one of three modes (the hub's Indicator):
 *           hidden; the day so far (hour ticks, spent part, red now-notch); or
 *           the playing track's position
 *   quick   the 設 button that opens the quick settings menu (a module like any other)
 */
Item {
    id: root

    required property var pal
    // Everything is sized in design pixels times k (screen scale * type size).
    property real k: 1
    property date now: new Date()
    property var spaces: []
    property string activeWorkspace: ""
    property string appClass: ""
    property string windowTitle: ""
    property string home: ""
    // { title, artist, progress, hasLength, playing } or null
    property var media: null
    property var volume: null
    property var network: null
    property var bluetooth: null
    property var battery: null
    property var brightness: null
    // [{ app, summary, urgent, glyph, tilt }], newest first
    property var notifications: []
    // [{ key, glyph, title, on, red }]
    property var indicators: []
    // True while the quick settings menu is open on this output (the 設 button stays inked).
    property bool quickOpen: false
    // Native Ryoku plugin discovery object, owned once by Scene.qml.
    property var pluginHost: null
    property string screenName: ""
    property string activePluginPanelId: ""

    readonly property var readings: {
        const out = []
        if (network) out.push({ key: "network", glyph: network.kind === "wifi" ? "網" : "線",
            value: network.off ? "OFF" : String(network.name || "ON"), brief: network.kind === "wifi" ? String(network.bars || 0) : "",
            level: network.kind === "wifi" ? Math.max(0, Math.min(1, Number(network.bars || 0) / 4)) : -1,
            fill: network.kind === "wifi" ? Math.max(0, Math.min(1, Number(network.bars || 0) / 4)) : 0,
            bars: network.kind === "wifi" ? Number(network.bars || 0) : -1, needsYou: !!network.needsYou, link: false })
        if (bluetooth) out.push({ key: "bluetooth", glyph: "双", value: bluetooth.enabled ? (bluetooth.connected ? "ON" : "ON") : "OFF",
            brief: bluetooth.connected ? "1" : "0", level: -1, fill: 0, bars: -1, needsYou: !bluetooth.enabled, link: true })
        if (volume) out.push({ key: "volume", glyph: "音", value: volume.muted ? "MUTE" : String(volume.percent), brief: String(volume.percent),
            level: Number(volume.level), fill: Number(volume.level), bars: -1, needsYou: !!volume.needsYou, link: false })
        if (brightness) out.push({ key: "brightness", glyph: "光", value: String(brightness.percent), brief: String(brightness.percent),
            level: Number(brightness.level), fill: Number(brightness.level), bars: -1, needsYou: false, link: false })
        if (battery) out.push({ key: "battery", glyph: "充", value: String(battery.percent), brief: String(battery.percent),
            level: Number(battery.level), fill: Number(battery.level), bars: -1, needsYou: !!battery.needsYou, link: false })
        return out
    }

    readonly property bool still: pal.still
    // Transitions wait until the bar has laid itself out, so nothing slides
    // or fades in from zero when the shell starts.
    property bool awake: false
    readonly property bool live: awake && !still
    Timer { interval: 1500; running: true; onTriggered: root.awake = true }
    readonly property int barHeight: height

    signal sealClicked(int button)
    signal workspaceActivated(string id)
    signal workspaceStepped(int delta)
    signal mediaAction(string name)
    signal clockClicked()
    signal statusAction(string name, string how)
    signal inboxAction(string how)
    signal indicatorAction(string key, string how)
    signal clearNotifications()
    signal quickClicked()
    signal pluginPanelRequested(string id, var api)

    function px(v) { return Math.round(v * root.k) }
    function controlRadius(w, h) {
        const m = Math.max(0, Math.min(Number(w || 0), Number(h || 0)))
        if (root.pal.shape === "pill") return m / 2
        if (root.pal.shape === "rounded") return Math.min(root.innerCorner, m / 2)
        return 0
    }

    readonly property bool compact: barHeight <= px(32)
    readonly property bool islands: pal.islands === true
    readonly property int islandPad: px(pal.islandPad)
    readonly property bool tall: barHeight >= px(44)

    readonly property int gap: px(pal.moduleGap)
    // Lane spread is continuous: 0 packs populated lanes with an exact
    // transparent channel between island papers; 1 restores Karuma's classic
    // outer / centre / outer composition. This makes islandGap a real geometry
    // control instead of a decorative setting that politely does nothing.
    readonly property real laneSpread: pal.laneSpread
    readonly property int islandSeparation: px(pal.islandGap)
    readonly property int packedZoneGap: islandSeparation + islandPad * 2
    function mixPos(packed, spread) { return packed + (spread - packed) * laneSpread }
    readonly property real packedTotalWidth: left.implicitWidth
        + (center.implicitWidth > 0 ? packedZoneGap + center.implicitWidth : 0)
        + (right.implicitWidth > 0 ? packedZoneGap + right.implicitWidth : 0)
    readonly property real packedStartX: Math.max(px(2), (width - packedTotalWidth) / 2)
    readonly property real leftPackedX: packedStartX
    readonly property real centerPackedX: leftPackedX + left.implicitWidth
        + (center.implicitWidth > 0 ? packedZoneGap : 0)
    readonly property real rightPackedX: (center.implicitWidth > 0 ? centerPackedX + center.implicitWidth : leftPackedX + left.implicitWidth)
        + (right.implicitWidth > 0 ? packedZoneGap : 0)
    readonly property real leftSpreadX: px(6) + inset
    readonly property real centerSpreadX: Math.max(0, (width - center.implicitWidth) / 2)
    readonly property real rightSpreadX: Math.max(0, width - right.implicitWidth - (px(10) + inset))
    readonly property int labelPx: Math.max(8, Math.round(px(10) * pal.textScale))
    readonly property int valuePx: Math.max(9, Math.round(px(13) * pal.textScale))
    readonly property int glossPx: Math.max(9, Math.round(px(12) * pal.textScale))
    readonly property real trackLabel: labelPx * 0.14

    // ------------------------------------------------------------ shape
    // Only a floating bar has curved corners; the palette already folds that in.
    readonly property real corner: pal.shape === "pill" ? height / 2
        : (pal.shape === "rounded" ? Math.min(px(pal.cornerRadius), height / 2) : 0)
    // Nested controls follow the same curve instead of carrying unrelated magic
    // radii. The bias is the user's one deliberate escape hatch from concentricity.
    readonly property real innerCorner: pal.shape === "pill" ? Math.max(0, (height - islandPad * 2) / 2)
        : Math.max(0, corner - Math.max(px(2), islandPad * 0.5) + px(pal.innerRadiusBias))
    // Keeps content clear of a curved end.
    readonly property real inset: Math.round(corner * 0.5)

    // ------------------------------------------------------------ module layout
    readonly property var configuredLeftIds: pal.leftKey.length ? pal.leftKey.split(",") : []
    readonly property var configuredCenterIds: pal.centerKey.length ? pal.centerKey.split(",") : []
    readonly property var configuredRightIds: pal.rightKey.length ? pal.rightKey.split(",") : []

    function isRyokuPlugin(id) { return String(id).indexOf("ryoku:") === 0 }
    function pluginId(id) { return isRyokuPlugin(id) ? String(id).slice(6) : "" }
    function pluginEnabled(ref) {
        if (!isRyokuPlugin(ref)) return true
        return root.pluginHost && root.pluginHost.isEnabled(root.pluginId(ref))
    }
    function effectiveLane(base, laneName) {
        const out = []
        for (let i = 0; i < base.length; ++i) {
            const id = String(base[i])
            if (!root.isRyokuPlugin(id) || root.pluginEnabled(id)) out.push(id)
        }
        if (root.pluginHost) {
            const ids = root.pluginHost.pluginIds || []
            for (let j = 0; j < ids.length; ++j) {
                const ref = "ryoku:" + ids[j]
                const placed = root.configuredLeftIds.indexOf(ref) >= 0
                    || root.configuredCenterIds.indexOf(ref) >= 0
                    || root.configuredRightIds.indexOf(ref) >= 0
                const preferred = root.pluginHost.defaultLane(ids[j])
                if (!placed && preferred === laneName && root.pal.moduleVisible(ref)) out.push(ref)
            }
        }
        return out
    }

    // Newly-enabled plugins that have never been placed use the lane declared in
    // manifest.defaults.bar.section (right when absent). Once the user moves one,
    // KarumaSchema persists the explicit lane and this auto-placement stops.
    readonly property var leftIds: effectiveLane(configuredLeftIds, "left")
    readonly property var centerIds: effectiveLane(configuredCenterIds, "center")
    readonly property var rightIds: effectiveLane(configuredRightIds, "right")

    // Modules that expose shared geometry/state register here.
    property Item regWorkspaces: null
    property Item regTitle: null
    property Item regStatus: null
    property Item regIndicators: null
    property Item regInbox: null
    property Item regQuick: null

    function moduleComponent(id) {
        switch (id) {
        case "workspaces": return cWorkspaces
        case "title": return cTitle
        case "clock": return cClock
        case "media": return cMedia
        case "tray": return cTray
        case "status": return cStatus
        case "indicators": return cIndicators
        case "notifications": return cInbox
        case "quick": return cQuick
        }
        return root.isRyokuPlugin(id) ? cRyokuPlugin : null
    }

    function moduleShown(item) { return item && item.shown === true }
    readonly property bool quickOnRight: rightIds.indexOf("quick") >= 0

    function moduleStyle(id) { return pal.moduleStyle(String(id)) }
    function stylePad(id) { return moduleStyle(id) === "plain" ? 0 : px(6) }
    function styleFill(id) {
        const style = moduleStyle(id)
        if (style === "accent") return pal.sealTint
        if (style === "paper") return pal.raised
        return "transparent"
    }
    function styleBorder(id) {
        const style = moduleStyle(id)
        if (style === "accent") return pal.sealEdge
        if (style === "outline") return pal.lineStrong
        if (style === "paper") return pal.line
        return "transparent"
    }

    // ------------------------------------------------------------ paper
    // The page the strip is printed on. Only this surface follows the opacity
    // setting; the ink on it stays fully drawn.
    Rectangle {
        anchors.fill: parent
        visible: !root.islands
        radius: root.corner
        antialiasing: true
        color: root.pal.alpha(root.pal.paper, root.pal.barOpacity)
        border.width: root.pal.floating ? root.pal.borderWidth : 0
        border.color: root.pal.alpha(root.pal.line, root.pal.borderOpacity)
    }

    // Islands keeps the normal spread layout, but prints each region on its own
    // paper pill. The transparent channels between them remain real desktop.
    Item {
        id: leftIslandHit
        visible: root.islands && left.implicitWidth > 0
        x: Math.max(0, left.x - root.islandPad)
        y: 0
        width: Math.min(root.width - x, left.implicitWidth + root.islandPad * 2)
        height: root.height
    }
    Item {
        id: centerIslandHit
        visible: root.islands && center.implicitWidth > 0
        x: Math.max(0, center.x - root.islandPad)
        y: 0
        width: Math.min(root.width - x, center.implicitWidth + root.islandPad * 2)
        height: root.height
    }
    Item {
        id: rightIslandHit
        visible: root.islands && right.implicitWidth > 0
        x: Math.max(0, right.x - root.islandPad)
        y: 0
        width: Math.min(root.width - x, right.implicitWidth + root.islandPad * 2)
        height: root.height
    }

    property alias leftIslandRegion: leftIslandHit
    property alias centerIslandRegion: centerIslandHit
    property alias rightIslandRegion: rightIslandHit

    Repeater {
        model: root.islands ? [leftIslandHit, centerIslandHit, rightIslandHit] : []
        delegate: Rectangle {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            visible: modelData.visible && modelData.width > 0
            radius: root.corner
            antialiasing: true
            color: root.pal.alpha(root.pal.paper, root.pal.barOpacity)
            border.width: root.pal.borderWidth
            border.color: root.pal.alpha(root.pal.line, root.pal.borderOpacity)
        }
    }

    // ------------------------------------------------------------ progress
    // Strip can span the whole bar. Islands deliberately cannot: automatic
    // progress belongs to the centre island so no line bridges transparent gaps.
    // Module placement moves music into the media module and daily progress into
    // the clock module; those components draw their own local track.
    Item {
        id: edge
        readonly property string mode: root.pal.indicatorMode
        readonly property bool daily: mode === "daily"
        readonly property bool trackKnown: root.media !== null && root.media.hasLength === true
        readonly property bool trackPlaying: trackKnown && root.media.playing === true
        readonly property real goal: daily ? HD.dayFraction(root.now) : (trackKnown ? HD.clamp01(root.media.progress) : 0)
        readonly property bool marked: daily || trackKnown
        readonly property real vigor: (daily || trackPlaying ? 1 : 0.45) * root.pal.progressOpacity
        readonly property string placement: root.pal.progressPlacement === "auto"
            ? (root.islands ? "center" : "whole") : root.pal.progressPlacement
        readonly property bool local: placement === "module"
        readonly property Item target: placement === "left" ? leftIslandHit
            : placement === "center" ? centerIslandHit
            : placement === "right" ? rightIslandHit : null
        readonly property real targetX: target ? target.x : 0
        readonly property real targetW: target ? target.width : root.width
        readonly property int thick: root.px(root.pal.progressThickness)

        x: targetX
        y: root.height - Math.max(thick, root.px(2))
        width: Math.max(0, targetW)
        height: Math.max(thick, root.px(2))
        visible: mode !== "disabled" && root.pal.progressStyle !== "none" && !local && width > 0
        opacity: visible ? 1 : 0
        Behavior on opacity { enabled: root.live; NumberAnimation { duration: 160 } }

        property real fraction: 0
        Component.onCompleted: fraction = goal
        onGoalChanged: {
            slide.stop()
            if (!root.live || !marked || Math.abs(goal - fraction) > 0.2) { fraction = goal; return }
            slide.duration = daily ? 1200 : 1000
            slide.easing.type = daily ? Easing.InOutSine : Easing.Linear
            slide.to = goal
            slide.restart()
        }
        onMarkedChanged: { slide.stop(); fraction = goal }
        NumberAnimation { id: slide; target: edge; property: "fraction" }

        readonly property int pad: root.px(10) + (target ? 0 : root.inset)
        Item {
            id: rod
            x: edge.pad
            width: Math.max(0, edge.width - edge.pad * 2)
            height: edge.height

            readonly property bool hairline: root.pal.progressStyle === "hairline"
            readonly property real trackH: hairline ? 1 : Math.max(1, edge.thick)
            // Track colour; its transparent twin keeps the fade free of grey fringes.
            readonly property color trackColor: hairline ? root.pal.progressHairline : root.pal.progressTrack
            readonly property color trackClear: Qt.rgba(trackColor.r, trackColor.g, trackColor.b, 0)
            readonly property color fillColor: root.pal.progressStyle === "accent" ? root.pal.progress : root.pal.progressSoft

            Rectangle {
                anchors.fill: parent
                visible: root.pal.progressStyle === "fill"
                radius: height / 2
                color: root.pal.alpha(root.pal.progress, 0.10 * edge.vigor)
            }
            // The empty rod: fades out at both the left and the right end.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: rod.trackH
                radius: height / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: rod.trackClear }
                    GradientStop { position: 0.06; color: rod.trackColor }
                    GradientStop { position: 0.94; color: rod.trackColor }
                    GradientStop { position: 1; color: rod.trackClear }
                }
            }
            // The spent part (of the day, or of the track) as one stroke of ink,
            // fading in from the left edge.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.round(parent.width * edge.fraction))
                height: rod.trackH
                radius: height / 2
                opacity: edge.marked ? edge.vigor : 0
                Behavior on opacity { enabled: root.live; NumberAnimation { duration: 180 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(rod.fillColor.r, rod.fillColor.g, rod.fillColor.b, 0) }
                    GradientStop { position: 0.35; color: Qt.rgba(rod.fillColor.r, rod.fillColor.g, rod.fillColor.b, 0.35) }
                    GradientStop { position: 1; color: rod.fillColor }
                }
            }
            // Hour marks point up from the rod, start to end. They belong to the day alone.
            Repeater {
                model: HD.hourTicks()
                Rectangle {
                    id: tick
                    required property var modelData
                    x: HD.at(tick.modelData.fraction, rod.width, 1)
                    y: Math.round(rod.height / 2 - rod.trackH / 2) - height
                    width: 1
                    height: root.px(tick.modelData.major ? 5 : 3)
                    color: tick.modelData.fraction <= HD.dayFraction(root.now) ? root.pal.progressTick : root.pal.progressTickDim
                    opacity: edge.daily ? root.pal.progressOpacity : 0
                    Behavior on opacity { enabled: root.live; NumberAnimation { duration: 180 } }
                }
            }
            Rectangle {
                visible: edge.marked && (root.pal.progressStyle === "track" || root.pal.progressStyle === "accent")
                x: Math.max(0, Math.round(parent.width * edge.fraction) - width / 2)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, edge.thick)
                height: Math.max(root.px(5), edge.thick * 2)
                radius: width / 2
                color: root.pal.progressNow
                opacity: edge.vigor
            }
        }
    }

    // ------------------------------------------------------------ three lane host
    // Strip and Islands share the exact same lane geometry. Islands only paint
    // three independent paper surfaces around these rows, so switching layout
    // never moves a module or changes its ordering.
    component LaneCell: Item {
        id: cell
        required property string moduleId
        readonly property string treatment: root.moduleStyle(moduleId)
        readonly property var options: root.pal.moduleOptions(moduleId)
        readonly property real moduleScale: options.scale
        readonly property int pad: root.stylePad(moduleId) + root.px(options.padding)
        readonly property bool occupied: loader.sourceComponent !== null
        readonly property bool shown: loader.item ? loader.item.shown === true : false
        readonly property real scaledWidth: loader.width * moduleScale
        width: shown ? scaledWidth + pad * 2 : 0
        height: root.barHeight
        visible: width > 0
        opacity: (treatment === "ghost" ? 0.52 : 1) * options.opacity

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: 0
            width: parent.width
            height: Math.max(root.px(24), Math.min(parent.height - root.px(4), root.px(30)))
            radius: treatment === "plain" ? 0 : Math.min(root.innerCorner, height / 2)
            visible: treatment !== "plain" && treatment !== "ghost" && cell.shown
            color: root.styleFill(cell.moduleId)
            border.width: treatment === "outline" || treatment === "paper" || treatment === "accent" ? root.pal.borderWidth : 0
            border.color: root.styleBorder(cell.moduleId)
        }

        Loader {
            id: loader
            x: cell.pad + (cell.scaledWidth - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            scale: cell.moduleScale
            transformOrigin: Item.Center
            sourceComponent: root.moduleComponent(cell.moduleId)
            onLoaded: {
                if (item && "moduleId" in item) item.moduleId = cell.moduleId
            }
        }
    }

    component LaneRow: Row {
        id: lane
        required property var ids
        spacing: root.gap
        height: root.barHeight
        Repeater {
            model: lane.ids
            delegate: LaneCell {
                required property string modelData
                moduleId: modelData
            }
        }
    }

    Row {
        id: left
        x: root.mixPos(root.leftPackedX, root.leftSpreadX)
        anchors { top: parent.top; bottom: parent.bottom }
        spacing: root.gap

        // The seal remains Karuma's fixed brand anchor. Everything after it is
        // data-driven and may move freely between lanes.
        Rectangle {
            id: seal
            readonly property int size: Math.round((root.compact ? root.px(22) : root.px(26)) * root.pal.iconScale)
            anchors.verticalCenter: parent.verticalCenter
            width: size
            height: size
            radius: root.controlRadius(width, height)
            color: root.pal.seal
            antialiasing: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: Math.max(2, Math.round(seal.size * 0.08))
                radius: Math.max(1, seal.radius - 1)
                color: "transparent"
                border.width: 1
                border.color: root.pal.alpha(root.pal.onSeal, 0.5)
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Math.round(seal.size * 0.02)
                text: root.pal.sealGlyph
                color: root.pal.onSeal
                font.family: root.pal.jp
                font.weight: Font.Medium
                font.pixelSize: Math.round(seal.size * 0.58)
                renderType: Text.NativeRendering
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => root.sealClicked(mouse.button)
                onWheel: (wheel) => root.workspaceStepped(wheel.angleDelta.y > 0 ? -1 : 1)
            }
        }

        LaneRow { ids: root.leftIds }
    }

    LaneRow {
        id: center
        ids: root.centerIds
        x: root.mixPos(root.centerPackedX, root.centerSpreadX)
        anchors.top: parent.top
        anchors.bottom: parent.bottom
    }

    LaneRow {
        id: right
        ids: root.rightIds
        x: root.mixPos(root.rightPackedX, root.rightSpreadX)
        anchors { top: parent.top; bottom: parent.bottom }
    }

    // ------------------------------------------------------------ modules
    Component {
        id: cClock
        Item {
            id: clockView
            property string moduleId: "clock"
            readonly property bool shown: root.pal.showTime || root.pal.showDate
            readonly property string timeText: Qt.formatTime(root.now, root.pal.hours === "24h" ? "HH:mm" : "h:mm AP")
            readonly property int colon: timeText.indexOf(":")
            readonly property string markup: colon < 0 ? timeText
                : timeText.slice(0, colon) + "<font color='" + String(root.pal.inkMuted) + "'>:</font>" + timeText.slice(colon + 1)
            readonly property int timePx: root.px(root.compact ? 18 : (root.tall ? 24 : 22))
            readonly property var dateParts: Schema.splitDate(root.pal.dateFormat)
            readonly property string dateTop: Qt.formatDate(root.now, dateParts.top).toUpperCase()
            readonly property string dateBottom: dateParts.bottom.length
                ? Qt.formatDate(root.now, dateParts.bottom).toUpperCase() : ""

            implicitWidth: shown ? clockRow.implicitWidth + root.px(8) : 0
            implicitHeight: root.barHeight
            width: implicitWidth
            height: implicitHeight

            Row {
                id: clockRow
                anchors.centerIn: parent
                spacing: 0

                Text {
                    id: clockTime
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pal.showTime
                    textFormat: Text.StyledText
                    text: clockView.markup
                    color: root.pal.ink
                    font.family: root.pal.display
                    font.pixelSize: clockView.timePx
                    font.weight: Font.Normal
                    font.variableAxes: root.pal.axes(clockView.timePx)
                    font.letterSpacing: 0.2
                    font.features: { "tnum": 1, "lnum": 1 }
                }

                Item {
                    id: dateBox
                    readonly property real lead: root.pal.showTime ? root.px(10) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.pal.showDate
                    width: visible ? lead + dateCol.implicitWidth : 0
                    height: dateCol.implicitHeight
                    Column {
                        id: dateCol
                        x: dateBox.lead
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.px(2)
                        Text {
                            text: root.compact && clockView.dateBottom.length
                                ? clockView.dateTop + " " + clockView.dateBottom : clockView.dateTop
                            color: root.compact || clockView.dateBottom.length === 0 ? root.pal.inkMuted : root.pal.inkDim
                            font.family: root.pal.mono
                            font.pixelSize: root.labelPx
                            font.weight: Font.Medium
                            font.letterSpacing: root.trackLabel
                        }
                        Text {
                            visible: !root.compact && clockView.dateBottom.length > 0
                            text: clockView.dateBottom
                            color: root.pal.inkMuted
                            font.family: root.pal.mono
                            font.pixelSize: root.labelPx
                            font.weight: Font.Medium
                            font.letterSpacing: root.trackLabel
                        }
                    }
                }
            }

            Item {
                id: dayBar
                visible: root.pal.progressPlacement === "module" && root.pal.indicatorMode === "daily"
                    && root.pal.progressStyle !== "none"
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: root.px(4); anchors.rightMargin: root.px(4)
                height: Math.max(1, root.px(root.pal.progressThickness))
                readonly property bool hairline: root.pal.progressStyle === "hairline"
                readonly property color trackColor: hairline ? root.pal.progressHairline : root.pal.progressTrack
                readonly property color fillColor: root.pal.progressStyle === "accent" ? root.pal.progress : root.pal.progressSoft
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(dayBar.trackColor.r, dayBar.trackColor.g, dayBar.trackColor.b, 0) }
                        GradientStop { position: 0.06; color: dayBar.trackColor }
                        GradientStop { position: 0.94; color: dayBar.trackColor }
                        GradientStop { position: 1; color: Qt.rgba(dayBar.trackColor.r, dayBar.trackColor.g, dayBar.trackColor.b, 0) }
                    }
                }
                Rectangle {
                    width: Math.round(parent.width * HD.dayFraction(root.now))
                    height: parent.height; radius: height / 2
                    opacity: root.pal.progressOpacity
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(dayBar.fillColor.r, dayBar.fillColor.g, dayBar.fillColor.b, 0) }
                        GradientStop { position: 0.35; color: Qt.rgba(dayBar.fillColor.r, dayBar.fillColor.g, dayBar.fillColor.b, 0.35) }
                        GradientStop { position: 1; color: dayBar.fillColor }
                    }
                }
                Repeater {
                    model: HD.hourTicks()
                    Rectangle {
                        id: dtick
                        required property var modelData
                        x: HD.at(dtick.modelData.fraction, dayBar.width, 1)
                        y: -height
                        width: 1
                        height: root.px(dtick.modelData.major ? 5 : 3)
                        color: dtick.modelData.fraction <= HD.dayFraction(root.now) ? root.pal.progressTick : root.pal.progressTickDim
                        opacity: root.pal.progressOpacity
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clockClicked()
            }
        }
    }

    Component {
        id: cRyokuPlugin
        Item {
            id: pluginView
            property string moduleId: ""
            readonly property string pid: root.pluginId(moduleId)
            readonly property var entry: root.pluginHost ? root.pluginHost.entryFor(pid) : null
            readonly property string versionQuery: entry && entry.version
                ? "?v=" + encodeURIComponent(entry.version) : ""
            readonly property bool shown: !!entry && root.pluginHost && root.pluginHost.isEnabled(pid)
            readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME")
                || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/plugins/" + pid
            implicitWidth: shown && contentSlot.item ? Math.max(1, contentSlot.item.implicitWidth) + root.px(8) : 0
            implicitHeight: root.barHeight
            width: implicitWidth
            height: implicitHeight

            property var api: QtObject {
                readonly property var mainInstance: serviceSlot.item
                readonly property var pluginSettings: (pluginView.entry && pluginView.entry.placement
                    && pluginView.entry.placement.settings) ? pluginView.entry.placement.settings : ({})
                readonly property string pluginDir: pluginView.entry ? pluginView.entry.dir : ""
                readonly property string stateDir: pluginView.stateRoot
                readonly property bool panelOpen: root.activePluginPanelId === pluginView.pid
                readonly property bool hasPanel: !!(pluginView.entry && pluginView.entry.manifest
                    && pluginView.entry.manifest.entryPoints && pluginView.entry.manifest.entryPoints.panel)
                function saveSetting(key, value) {
                    if (root.pluginHost) root.pluginHost.saveSetting(pluginView.pid, key, value)
                }
                function saveSettings() {}
                function openPanel() { if (hasPanel) root.pluginPanelRequested(pluginView.pid, this) }
                function closePanel() { if (panelOpen) root.pluginPanelRequested("", this) }
                function togglePanel() { root.pluginPanelRequested(panelOpen ? "" : pluginView.pid, this) }
                Component.onCompleted: if (stateDir.length) Quickshell.execDetached(["mkdir", "-p", stateDir])
            }

            PluginObjectSlot {
                id: serviceSlot
                source: pluginView.entry
                    ? "file://" + pluginView.entry.dir + "/service/Main.qml" + pluginView.versionQuery : ""
                configure: (service) => {
                    if (service && "pluginApi" in service) service.pluginApi = pluginView.api
                }
            }
            PluginObjectSlot {
                id: contentSlot
                width: contentSlot.item ? contentSlot.item.implicitWidth : 0
                height: contentSlot.item ? contentSlot.item.implicitHeight : 0
                anchors.centerIn: parent
                source: pluginView.entry
                    ? "file://" + pluginView.entry.dir + "/content/Widget.qml" + pluginView.versionQuery : ""
                configure: (content) => {
                    if (!content) return
                    if ("pluginApi" in content) content.pluginApi = pluginView.api
                    if ("density" in content) content.density = "glyph"
                    if ("widthBudget" in content) content.widthBudget = 220
                    if ("active" in content) content.active = true
                }
            }
        }
    }

    Component {
        id: cWorkspaces
        // Workspaces 頁: drawn in the style chosen in the hub (pal.workspaceStyle).
        //   kanji / numbers / roman  text on a plate that slides to the live one
        //   dashes                   bars; the live one stretches and turns to ink
        //   dots                     pips; occupied are filled, the live one is solid
        // Every cell keeps one fixed size per style, so nothing shifts when the
        // live workspace or the window counts change.
        Item {
            id: spacesView
            anchors.verticalCenter: parent.verticalCenter
            readonly property string style: root.pal.workspaceStyle
            readonly property bool textual: style === "kanji" || style === "numbers" || style === "roman"
            readonly property bool shown: root.spaces.length > 0
            Component.onCompleted: root.regWorkspaces = spacesView
            Component.onDestruction: if (root.regWorkspaces === spacesView) root.regWorkspaces = null
            implicitWidth: wsRow.implicitWidth
            implicitHeight: root.barHeight
            width: implicitWidth
            height: implicitHeight

            property Item liveCell: null
            function note(item: Item, on: bool) {
                if (on) liveCell = item;
                else if (liveCell === item) liveCell = null;
            }

            Rectangle {
                id: plate
                visible: spacesView.textual && spacesView.liveCell !== null
                x: wsRow.x + (spacesView.liveCell ? spacesView.liveCell.x : 0)
                y: wsRow.y + (spacesView.liveCell ? spacesView.liveCell.y : 0)
                width: spacesView.liveCell ? spacesView.liveCell.width : 0
                height: spacesView.liveCell ? spacesView.liveCell.height : 0
                radius: root.controlRadius(width, height)
                color: root.pal.bone
                Behavior on x { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on width { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            Row {
                id: wsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: spacesView.style === "dots" ? root.px(2) : (spacesView.style === "dashes" ? root.px(2) : root.px(3))

                Repeater {
                    model: root.spaces

                    Item {
                        id: cell
                        required property var modelData
                        readonly property bool on: String(modelData.id) === String(root.activeWorkspace)
                        readonly property bool occupied: modelData.count > 0
                        readonly property string face: Schema.workspaceText(spacesView.style, modelData.id, modelData.label)
                        onOnChanged: spacesView.note(cell, cell.on)
                        Component.onCompleted: spacesView.note(cell, cell.on)
                        Component.onDestruction: if (spacesView.liveCell === cell) spacesView.liveCell = null

                        readonly property real base: root.px(root.compact ? 22 : 24)
                        implicitWidth: spacesView.style === "dashes" ? root.px(root.compact ? 24 : 28)
                            : (spacesView.style === "dots" ? root.px(root.compact ? 14 : 16)
                            : Math.max(base, faceText.implicitWidth + root.px(10)))
                        implicitHeight: spacesView.textual ? base : root.px(root.compact ? 22 : 24)
                        width: implicitWidth
                        height: implicitHeight

                        Text {
                            id: faceText
                            visible: spacesView.textual
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: spacesView.style === "kanji" ? -1 : 0
                            text: cell.face
                            color: cell.on ? root.pal.boneInk : (cell.occupied ? root.pal.inkDim : root.pal.inkFaint)
                            font.family: spacesView.style === "kanji" ? root.pal.jp
                                : (spacesView.style === "roman" ? root.pal.display : root.pal.text)
                            font.pixelSize: spacesView.style === "kanji" ? root.px(13.5)
                                : (spacesView.style === "roman" ? root.px(13) : root.px(12.5))
                            font.weight: spacesView.style === "numbers" ? Font.Medium : Font.Normal
                            Behavior on color { enabled: root.live; ColorAnimation { duration: 140 } }
                        }

                        // A pip for each window on a page you are not on (text styles).
                        Row {
                            visible: spacesView.textual && !cell.on && cell.occupied
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 1
                            spacing: 2
                            Repeater {
                                model: Math.min(cell.modelData.count, 5)
                                Rectangle { width: 2; height: 2; color: root.pal.inkDim; opacity: 0.7 }
                            }
                        }

                        // Dashes: a bar per workspace. Empty = faint hairline, occupied = dim,
                        // live = ink and stretched to the full cell.
                        Rectangle {
                            visible: spacesView.style === "dashes"
                            anchors.centerIn: parent
                            height: cell.on ? root.px(3) : root.px(2)
                            width: cell.on ? cell.width - root.px(2) : Math.round(cell.width * 0.5)
                            radius: height / 2
                            color: cell.on ? root.pal.bone : (cell.occupied ? root.pal.inkDim : root.pal.inkFaint)
                            opacity: cell.on || cell.occupied ? 1 : 0.7
                            Behavior on width { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on height { enabled: root.live; NumberAnimation { duration: 160 } }
                            Behavior on color { enabled: root.live; ColorAnimation { duration: 140 } }
                        }

                        // Dots: ring when empty, filled when it holds windows, larger and solid when live.
                        Rectangle {
                            visible: spacesView.style === "dots"
                            anchors.centerIn: parent
                            width: cell.on ? root.px(9) : root.px(6)
                            height: width
                            radius: width / 2
                            color: cell.on ? root.pal.bone : (cell.occupied ? root.pal.inkDim : "transparent")
                            border.width: cell.on || cell.occupied ? 0 : 1
                            border.color: root.pal.inkFaint
                            Behavior on width { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on color { enabled: root.live; ColorAnimation { duration: 140 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -2
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.workspaceActivated(String(cell.modelData.id))
                        }
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => root.workspaceStepped(event.angleDelta.y > 0 ? -1 : 1)
            }
        }
    }

    Component {
        id: cTitle
        // Window title 窓, byline: the app in serif italic, the title in grotesk.
        Item {
            id: titleView
            readonly property var parts: TitleJs.describe(root.appClass, TitleJs.tildify(root.windowTitle, root.home))
            readonly property bool empty: parts.app === "" && parts.head === "" && parts.leaf === ""
            // A lane owns placement now, so the title only owns its own width.
            // The fixed cap keeps one verbose application from swallowing a lane.
            readonly property real maxWidth: root.px(240)
            Component.onCompleted: root.regTitle = titleView
            Component.onDestruction: if (root.regTitle === titleView) root.regTitle = null

            anchors.verticalCenter: parent.verticalCenter
            readonly property bool shown: !empty
            width: shown ? Math.min(maxWidth, byline.implicitWidth) : 0
            height: root.barHeight
            clip: true

            function styled(headColor, dirColor, leafColor) {
                const p = parts;
                const out = [];
                if (p.head !== "")
                    out.push("<font color='" + headColor + "'>" + HD.esc(p.head) + "</font>");
                if (p.dir !== "" || p.leaf !== "")
                    out.push("<font color='" + dirColor + "'>" + HD.esc(p.dir) + "</font><font color='" + leafColor + "'>" + HD.esc(p.leaf) + "</font>");
                return out.join(" · ");
            }

            Row {
                id: byline
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(9)

                Text {
                    id: appName
                    anchors.baseline: restText.baseline
                    visible: text !== ""
                    text: titleView.parts.app
                    color: root.pal.ink
                    font.family: root.pal.display
                    font.italic: true
                    font.pixelSize: root.px(15)
                    font.weight: Font.Normal
                    font.variableAxes: root.pal.axes(root.px(15))
                }

                Text {
                    id: restText
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Math.max(0, titleView.maxWidth - (appName.visible ? appName.implicitWidth + byline.spacing : 0)))
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    text: titleView.styled(String(root.pal.inkMuted), String(root.pal.inkMuted), String(root.pal.inkDim))
                    color: root.pal.inkMuted
                    font.family: root.pal.text
                    font.pixelSize: root.valuePx
                }
            }
        }
    }

    Component {
        id: cMedia
        // 骨·玖 lzrb9GEd3xJS-P1p4RBBBe-UYsXA
        // Now playing 再生: the song in serif italic; the underline is the progress bar.
        Item {
            id: mediaView
            anchors.verticalCenter: parent.verticalCenter
            readonly property real maxWidth: root.px(260)
            readonly property bool shown: root.media !== null
            width: shown ? Math.min(maxWidth, under.implicitWidth) : 0
            height: root.barHeight
            clip: true

            readonly property color songInk: root.media && root.media.playing ? root.pal.ink : root.pal.inkDim

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => root.mediaAction(mouse.button === Qt.MiddleButton ? "next" : "open")
                onWheel: (wheel) => root.mediaAction(wheel.angleDelta.y > 0 ? "previous" : "next")
            }

            Column {
                id: under
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: root.px(6)
                rightPadding: root.px(6)
                spacing: root.px(3)

                Row {
                    id: mediaLine
                    spacing: root.px(5)
                    readonly property real room: mediaView.maxWidth - root.px(12)

                    Text {
                        id: song
                        anchors.baseline: artist.baseline
                        width: Math.min(implicitWidth, mediaLine.room * 0.62)
                        elide: Text.ElideRight
                        text: root.media ? String(root.media.title) : ""
                        color: mediaView.songInk
                        font.family: root.pal.display
                        font.italic: true
                        font.pixelSize: root.px(14)
                        font.weight: Font.Normal
                        font.variableAxes: root.pal.axes(root.px(14))
                    }
                    Text {
                        id: artist
                        visible: text !== ""
                        width: Math.min(implicitWidth, Math.max(0, mediaLine.room - song.width - mediaLine.spacing))
                        elide: Text.ElideRight
                        text: root.media && root.media.artist ? "· " + root.media.artist : ""
                        color: root.pal.inkDim
                        font.family: root.pal.text
                        font.pixelSize: root.valuePx
                    }
                }

                Item {
                    width: mediaLine.width
                    height: visible ? Math.max(1, root.px(root.pal.progressThickness)) : 0
                    visible: root.pal.indicatorMode === "music" && root.pal.progressPlacement === "module"
                        && root.pal.progressStyle !== "none"
                    id: musicBar
                    readonly property bool hairline: root.pal.progressStyle === "hairline"
                    readonly property color trackColor: hairline ? root.pal.progressHairline : root.pal.progressTrack
                    readonly property color fillColor: root.pal.progressStyle === "accent" ? root.pal.progress : root.pal.progressSoft
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.rgba(musicBar.trackColor.r, musicBar.trackColor.g, musicBar.trackColor.b, 0) }
                            GradientStop { position: 0.06; color: musicBar.trackColor }
                            GradientStop { position: 0.94; color: musicBar.trackColor }
                            GradientStop { position: 1; color: Qt.rgba(musicBar.trackColor.r, musicBar.trackColor.g, musicBar.trackColor.b, 0) }
                        }
                    }
                    Rectangle {
                        id: run
                        width: Math.round(parent.width * (root.media ? HD.clamp01(root.media.progress) : 0))
                        height: parent.height
                        radius: height / 2
                        opacity: root.pal.progressOpacity
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.rgba(musicBar.fillColor.r, musicBar.fillColor.g, musicBar.fillColor.b, 0) }
                            GradientStop { position: 0.35; color: Qt.rgba(musicBar.fillColor.r, musicBar.fillColor.g, musicBar.fillColor.b, 0.35) }
                            GradientStop { position: 1; color: musicBar.fillColor }
                        }
                    }
                    Rectangle {
                        x: Math.max(0, run.width - width / 2); anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, parent.height); height: Math.max(root.px(5), parent.height * 2)
                        radius: width / 2; color: root.pal.progressNow
                        visible: run.width > 0 && (root.pal.progressStyle === "track" || root.pal.progressStyle === "accent")
                    }
                }
            }
        }
    }

    Component {
        id: cStatus
        // 骨·弐 RKHF807YR0sYs7PZYbe_vpOgeJnH
        // Status 音, "ma": kanji and figure, a hairline fill under each level;
        // groups held apart by space, not fenced by lines.
        Row {
            id: status
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool shown: root.readings.length > 0
            Component.onCompleted: root.regStatus = status
            Component.onDestruction: if (root.regStatus === status) root.regStatus = null
            height: root.barHeight
            spacing: 0

            Repeater {
                model: root.readings

                Row {
                    id: slot
                    required property var modelData
                    required property int index
                    height: status.height

                    Item {
                        visible: slot.index > 0
                        readonly property bool groupEnds: slot.index > 0 && !!root.readings[slot.index - 1].link && !slot.modelData.link
                        width: groupEnds ? root.px(30) : root.px(16)
                        height: parent.height
                    }

                    Item {
                        id: reading
                        readonly property var r: slot.modelData
                        readonly property bool quantity: r.level >= 0
                        readonly property color valueInk: r.needsYou ? root.pal.urgent : root.pal.ink
                        readonly property string val: String(r.value) + "|" + r.level
                        property bool fresh: false
                        onValChanged: { if (root.live) { fresh = true; settle.restart(); } }
                        Timer { id: settle; interval: 900; onTriggered: reading.fresh = false }
                        readonly property bool lit: hover.containsMouse || fresh
                        readonly property color labelInk: lit ? root.pal.ink : root.pal.inkMuted

                        implicitWidth: maLine.implicitWidth
                        width: implicitWidth
                        height: root.barHeight

                        // Under the pointer a reading sits on a faint plate.
                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -root.px(6)
                            anchors.rightMargin: -root.px(6)
                            anchors.topMargin: root.px(5)
                            anchors.bottomMargin: root.px(5)
                            radius: Math.min(root.innerCorner, height / 2)
                            color: root.pal.alpha(root.pal.bone, hover.pressed ? (root.pal.light ? 0.12 : 0.10) : (root.pal.light ? 0.07 : 0.055))
                            opacity: hover.containsMouse ? 1 : 0
                            Behavior on opacity { enabled: root.live; NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => root.statusAction(reading.r.key, mouse.button === Qt.MiddleButton ? "middle" : (mouse.button === Qt.RightButton ? "right" : "click"))
                            onWheel: (wheel) => root.statusAction(reading.r.key, wheel.angleDelta.y > 0 ? "up" : "down")
                        }

                        Row {
                            id: maLine
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: reading.quantity && !root.compact ? -root.px(2) : 0
                            spacing: root.px(6)

                            Text {
                                anchors.baseline: maValue.baseline
                                text: reading.r.glyph
                                color: reading.r.needsYou ? root.pal.urgent : reading.labelInk
                                font.family: root.pal.jp
                                font.pixelSize: root.glossPx
                                Behavior on color { enabled: root.live; ColorAnimation { duration: 200 } }
                            }
                            RollText {
                                id: maValue
                                live: root.live
                                figure: reading.r.link ? String(reading.r.brief) : String(reading.r.value)
                                color: reading.valueInk
                                font.family: root.pal.text
                                font.pixelSize: root.valuePx
                                font.weight: Font.Medium
                                font.variableAxes: root.pal.valueAxes
                                font.features: { "tnum": 1 }
                            }
                            // Four rising Wi-Fi bars.
                            Row {
                                anchors.bottom: maValue.baseline
                                visible: reading.r.bars >= 0
                                spacing: 2
                                Repeater {
                                    model: 4
                                    Rectangle {
                                        required property int index
                                        y: root.px(9) - height
                                        width: 3
                                        height: root.px(3 + index * 2)
                                        color: index < reading.r.bars ? root.pal.ink : root.pal.inkFaint
                                    }
                                }
                            }
                        }

                        // The level as a hairline under the figure: the ink is the
                        // reading, the faint rest its range.
                        Rectangle {
                            visible: reading.quantity && !reading.r.link && !root.compact
                            x: maLine.x + maValue.x
                            anchors.top: maLine.bottom
                            anchors.topMargin: root.px(2)
                            width: Math.max(maValue.width, root.px(18))
                            height: 2
                            color: root.pal.lineSoft
                            Rectangle {
                                width: Math.max(reading.r.fill > 0 ? 2 : 0, Math.round(parent.width * (reading.r.fill || 0)))
                                height: parent.height
                                color: reading.r.needsYou ? root.pal.urgent : root.pal.ink
                                Behavior on width { enabled: root.live; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: cIndicators
        // Indicator stamps: small seals carrying a kanji. On, one is pressed,
        // slightly askew and inked (red only for "now"); off, a faint outline.
        Row {
            id: indicatorsRow
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool shown: root.indicators.length > 0
            Component.onCompleted: root.regIndicators = indicatorsRow
            Component.onDestruction: if (root.regIndicators === indicatorsRow) root.regIndicators = null
            spacing: root.px(5)

            Repeater {
                model: root.indicators

                Item {
                    id: ind
                    required property var modelData
                    readonly property bool on: modelData.on !== false
                    readonly property bool red: !!modelData.red
                    readonly property color plate: red ? root.pal.seal : root.pal.bone
                    readonly property color plateInk: red ? root.pal.onSeal : root.pal.boneInk

                    width: stamp.width
                    height: root.barHeight
                    opacity: on ? 1 : (pointer.hovered ? 0.85 : 0.4)
                    Behavior on opacity { enabled: root.live; NumberAnimation { duration: 140 } }

                    Rectangle {
                        id: stamp
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.px(18)
                        height: width
                        radius: Math.min(root.innerCorner, width / 2)
                        antialiasing: true
                        color: ind.on ? ind.plate : "transparent"
                        border.width: 1.5
                        border.color: ind.on ? ind.plate : root.pal.line
                        rotation: ind.on && !pointer.hovered ? HD.tilt(ind.modelData.key) : 0
                        Behavior on rotation { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        Rectangle {
                            visible: ind.on
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Math.max(0, stamp.radius - 2)
                            color: "transparent"
                            border.width: 1
                            border.color: root.pal.alpha(ind.plateInk, 0.45)
                        }
                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -0.5
                            text: String(ind.modelData.glyph)
                            color: ind.on ? ind.plateInk : root.pal.inkFaint
                            font.family: root.pal.jp
                            font.weight: Font.Medium
                            font.pixelSize: root.px(10.5)
                        }
                    }

                    HoverHandler { id: pointer }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => root.indicatorAction(ind.modelData.key, mouse.button === Qt.MiddleButton ? "middle" : (mouse.button === Qt.RightButton ? "right" : "click"))
                    }
                }
            }
        }
    }

    Component {
        id: cInbox
        // Notifications 報: each a small stamped seal of its app's initial,
        // slightly askew, newest on top; hover fans them out. The number is
        // how many wait.
        Item {
            id: inbox
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool shown: true
            Component.onCompleted: { root.regInbox = inbox; inbox.syncStamps(); }
            Component.onDestruction: if (root.regInbox === inbox) root.regInbox = null
            implicitWidth: stampRow.implicitWidth
            width: implicitWidth
            height: root.barHeight

            readonly property int count: root.notifications.length
            readonly property var stamps: root.notifications.slice(0, 3)
            readonly property bool fanned: inboxHover.hovered

            // The pile is drawn from a model that lags the live list, so a new stamp can
            // be pressed in and a cleared one can fade out before it is dropped. Rows
            // are matched by notification key; a row being cleared is marked `leaving`
            // and removed by its own animation. With animations off (or before the bar
            // has settled) rows simply appear and disappear.
            ListModel { id: stampModel }

            function dropStamp(key) {
                for (let i = 0; i < stampModel.count; ++i) {
                    const row = stampModel.get(i);
                    if (row.stampKey === key && row.leaving) { stampModel.remove(i); return; }
                }
            }
            function syncStamps() {
                const want = inbox.stamps;
                const wanted = ({});
                for (let i = 0; i < want.length; ++i) wanted[String(want[i].key)] = true;
                for (let j = stampModel.count - 1; j >= 0; --j) {
                    const row = stampModel.get(j);
                    if (wanted[row.stampKey]) continue;
                    if (root.live) { if (!row.leaving) stampModel.setProperty(j, "leaving", true); }
                    else stampModel.remove(j);
                }
                for (let k = 0; k < want.length; ++k) {
                    const n = want[k];
                    const key = String(n.key);
                    let at = -1;
                    for (let m = 0; m < stampModel.count; ++m)
                        if (stampModel.get(m).stampKey === key) { at = m; break; }
                    const data = { stampKey: key, glyph: String(n.glyph || ""), urgent: !!n.urgent, tilt: Number(n.tilt) || 0, leaving: false };
                    if (at < 0) stampModel.insert(Math.min(k, stampModel.count), data);
                    else stampModel.set(at, data);
                }
            }
            onStampsChanged: syncStamps()

            HoverHandler { id: inboxHover }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => root.inboxAction(mouse.button === Qt.RightButton ? "right" : (mouse.button === Qt.MiddleButton ? "middle" : "click"))
            }

            Row {
                id: stampRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.px(8)

                Row {
                    id: pile
                    anchors.verticalCenter: parent.verticalCenter
                    visible: stampModel.count > 0
                    spacing: inbox.fanned ? root.px(4) : -root.px(4)
                    Behavior on spacing { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    Repeater {
                        model: stampModel

                        Rectangle {
                            id: nstamp
                            required property string stampKey
                            required property string glyph
                            required property bool urgent
                            required property real tilt
                            required property bool leaving
                            required property int index
                            readonly property bool solid: urgent
                            readonly property bool latin: /^[A-Z0-9]$/.test(glyph)
                            z: stampModel.count - index
                            width: root.px(18)
                            height: width
                            radius: Math.min(root.innerCorner, width / 2)
                            antialiasing: true
                            rotation: inbox.fanned ? 0 : tilt
                            Behavior on rotation { enabled: root.live; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            color: solid ? root.pal.seal : root.pal.paper
                            border.width: 1.5
                            border.color: root.pal.seal

                            // Pressed in like a stamp: a touch large, settling onto the page.
                            Component.onCompleted: { if (root.live && !nstamp.leaving) enter.start(); }
                            ParallelAnimation {
                                id: enter
                                NumberAnimation { target: nstamp; property: "scale"; from: 1.45; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                NumberAnimation { target: nstamp; property: "opacity"; from: 0; to: 1; duration: 160 }
                            }
                            // A stamp whose notification came back mid-fade is put back whole.
                            onLeavingChanged: { if (!nstamp.leaving) { nstamp.scale = 1; nstamp.opacity = 1; } }
                            // Lifted off again: shrinks and fades, then its row is dropped.
                            SequentialAnimation {
                                id: leave
                                running: nstamp.leaving
                                ParallelAnimation {
                                    NumberAnimation { target: nstamp; property: "scale"; to: 0.6; duration: 170; easing.type: Easing.InCubic }
                                    NumberAnimation { target: nstamp; property: "opacity"; to: 0; duration: 170 }
                                }
                                ScriptAction { script: inbox.dropStamp(nstamp.stampKey) }
                            }

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -0.5
                                text: nstamp.glyph
                                color: nstamp.solid ? root.pal.paper : root.pal.seal
                                font.family: nstamp.latin ? root.pal.display : root.pal.jp
                                font.pixelSize: root.px(nstamp.latin ? 12 : 11)
                                font.variableAxes: nstamp.latin ? ({ "opsz": 14, "wght": 500 }) : ({})
                            }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: HD.count2(inbox.count)
                    color: inbox.count > 0 ? root.pal.inkMuted : root.pal.inkFaint
                    font.family: root.pal.mono
                    font.pixelSize: root.labelPx
                    font.weight: Font.Medium
                    font.letterSpacing: root.trackLabel
                }

                // Clears every waiting notification (the shell's own list, not
                // just this display). Only offered while something waits; the
                // stamps and the count going away are the confirmation.
                Rectangle {
                    id: clearBtn
                    visible: inbox.count > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.px(18)
                    height: width
                    radius: Math.min(root.innerCorner, width / 2)
                    antialiasing: true
                    color: clearHover.hovered ? root.pal.bone : "transparent"
                    border.width: 1.5
                    border.color: clearHover.hovered ? root.pal.bone : root.pal.line

                    Text {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -0.5
                        text: "消"
                        color: clearHover.hovered ? root.pal.boneInk : root.pal.inkMuted
                        font.family: root.pal.jp
                        font.weight: Font.Medium
                        font.pixelSize: root.px(10.5)
                    }

                    HoverHandler { id: clearHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.clearNotifications()
                    }
                }
            }
        }
    }

    Component {
        id: cTray
        // App tray 駐: the arrow that slides the background apps' icons out.
        KarumaTray {
            anchors.verticalCenter: parent.verticalCenter
            pal: root.pal
            unit: root.k
            innerCorner: root.innerCorner
            live: root.live
            vertical: false
            edge: root.pal.edge
        }
    }

    Component {
        id: cQuick
        // Quick settings 設: a small stamp that opens the quick settings menu. It is a
        // module like the others, so the hub can move or hide it. Inked while the menu is open.
        Item {
            id: quickBtn
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool shown: true
            readonly property bool lit: root.quickOpen || qHover.hovered
            Component.onCompleted: root.regQuick = quickBtn
            Component.onDestruction: if (root.regQuick === quickBtn) root.regQuick = null
            width: qStamp.width
            height: root.barHeight

            Rectangle {
                id: qStamp
                anchors.verticalCenter: parent.verticalCenter
                width: root.px(22)
                height: width
                radius: Math.min(root.innerCorner, width / 2)
                antialiasing: true
                color: quickBtn.lit ? root.pal.bone : "transparent"
                border.width: 1.5
                border.color: quickBtn.lit ? root.pal.bone : root.pal.line
                Behavior on color { enabled: root.live; ColorAnimation { duration: 140 } }
                Behavior on border.color { enabled: root.live; ColorAnimation { duration: 140 } }

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -0.5
                    text: "設"
                    color: quickBtn.lit ? root.pal.boneInk : root.pal.inkMuted
                    font.family: root.pal.jp
                    font.weight: Font.Medium
                    font.pixelSize: root.px(12)
                    Behavior on color { enabled: root.live; ColorAnimation { duration: 140 } }
                }
            }

            HoverHandler { id: qHover }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.quickClicked()
            }
        }
    }
}
