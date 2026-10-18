pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Ryoku.PluginKit
import "KarumaData.js" as HD
import "KarumaSchema.js" as Schema

// Native vertical Karuma renderer. It uses the same three-lane data as the
// horizontal bar; left/centre/right simply become top/middle/bottom on a rail.
// Nothing is rotated, so text, plugins and click targets stay normal Wayland UI.
Item {
    id: root

    required property var pal
    property real k: 1
    property date now: new Date()
    property var spaces: []
    property string activeWorkspace: ""
    property string appClass: ""
    property string windowTitle: ""
    property string home: ""
    property var media: null
    property var volume: null
    property var network: null
    property var bluetooth: null
    property var battery: null
    property var brightness: null
    property var notifications: []
    property var indicators: []
    property bool quickOpen: false
    property var pluginHost: null
    property string screenName: ""
    property string activePluginPanelId: ""

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
    function isRyokuPlugin(id) { return String(id).indexOf("ryoku:") === 0 }
    function pluginId(id) { return isRyokuPlugin(id) ? String(id).slice(6) : "" }
    function pluginEnabled(ref) {
        return !isRyokuPlugin(ref) || (root.pluginHost && root.pluginHost.isEnabled(root.pluginId(ref)))
    }

    readonly property bool islands: pal.islands === true
    readonly property int islandPad: px(pal.islandPad)
    readonly property int gap: px(Math.max(2, pal.moduleGap))
    readonly property real laneSpread: pal.laneSpread
    readonly property int islandSeparation: px(pal.islandGap)
    readonly property int packedZoneGap: islandSeparation + islandPad * 2
    function mixPos(packed, spread) { return packed + (spread - packed) * laneSpread }
    readonly property real packedTotalHeight: topZone.implicitHeight
        + (middleZone.implicitHeight > 0 ? packedZoneGap + middleZone.implicitHeight : 0)
        + (bottomZone.implicitHeight > 0 ? packedZoneGap + bottomZone.implicitHeight : 0)
    readonly property real packedStartY: Math.max(0, (height - packedTotalHeight) / 2)
    readonly property real topPackedY: packedStartY
    readonly property real middlePackedY: topPackedY + topZone.implicitHeight
        + (middleZone.implicitHeight > 0 ? packedZoneGap : 0)
    readonly property real bottomPackedY: (middleZone.implicitHeight > 0 ? middlePackedY + middleZone.implicitHeight : topPackedY + topZone.implicitHeight)
        + (bottomZone.implicitHeight > 0 ? packedZoneGap : 0)
    readonly property real topSpreadY: islandPad
    readonly property real middleSpreadY: Math.max(0, (height - middleZone.implicitHeight) / 2)
    readonly property real bottomSpreadY: Math.max(0, height - islandPad - bottomZone.implicitHeight)
    readonly property int railW: width
    readonly property real corner: pal.shape === "pill" ? width / 2
        : (pal.shape === "rounded" ? Math.min(px(pal.cornerRadius), width / 2) : 0)
    readonly property real innerCorner: pal.shape === "pill" ? Math.max(0, (width - islandPad * 2) / 2)
        : Math.max(0, corner - Math.max(px(2), islandPad * 0.5) + px(pal.innerRadiusBias))
    readonly property int labelPx: Math.max(8, Math.round(px(10) * pal.textScale))
    readonly property int valuePx: Math.max(9, Math.round(px(12) * pal.textScale))
    readonly property int iconPx: Math.max(12, Math.round(px(16) * pal.iconScale))

    readonly property var configuredLeftIds: pal.leftKey.length ? pal.leftKey.split(",") : []
    readonly property var configuredCenterIds: pal.centerKey.length ? pal.centerKey.split(",") : []
    readonly property var configuredRightIds: pal.rightKey.length ? pal.rightKey.split(",") : []

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
                if (!placed && root.pluginHost.defaultLane(ids[j]) === laneName && root.pal.moduleVisible(ref))
                    out.push(ref)
            }
        }
        return out
    }

    readonly property var leftIds: effectiveLane(configuredLeftIds, "left")
    readonly property var centerIds: effectiveLane(configuredCenterIds, "center")
    readonly property var rightIds: effectiveLane(configuredRightIds, "right")
    readonly property bool quickOnRight: rightIds.indexOf("quick") >= 0

    function moduleStyle(id) { return pal.moduleStyle(String(id)) }
    function styleFill(id) {
        const s = moduleStyle(id)
        return s === "accent" ? pal.sealTint : (s === "paper" ? pal.raised : "transparent")
    }
    function styleBorder(id) {
        const s = moduleStyle(id)
        return s === "accent" ? pal.sealEdge : (s === "outline" ? pal.lineStrong : pal.line)
    }

    Rectangle {
        anchors.fill: parent
        visible: !root.islands
        radius: root.corner
        color: root.pal.alpha(root.pal.paper, root.pal.barOpacity)
        border.width: root.pal.floating ? root.pal.borderWidth : 0
        border.color: root.pal.alpha(root.pal.line, root.pal.borderOpacity)
        antialiasing: true
    }

    Column {
        id: topZone
        x: root.islandPad
        y: root.mixPos(root.topPackedY, root.topSpreadY)
        width: Math.max(0, root.width - root.islandPad * 2)
        height: implicitHeight
        spacing: root.gap

        Rectangle {
            id: seal
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, Math.round(root.px(30) * root.pal.iconScale))
            height: width
            radius: root.controlRadius(width, height)
            color: root.pal.seal
            border.width: Math.max(0, root.pal.borderWidth)
            border.color: root.pal.alpha(root.pal.onSeal, 0.45)
            Text {
                anchors.centerIn: parent
                text: root.pal.sealGlyph
                color: root.pal.onSeal
                font.family: root.pal.jp
                font.pixelSize: Math.round(parent.width * 0.55)
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => root.sealClicked(mouse.button)
                onWheel: wheel => root.workspaceStepped(wheel.angleDelta.y > 0 ? -1 : 1)
            }
        }
        RailLane { width: parent.width; height: implicitHeight; ids: root.leftIds }
    }

    RailLane {
        id: middleZone
        ids: root.centerIds
        x: root.islandPad
        width: Math.max(0, root.width - root.islandPad * 2)
        height: implicitHeight
        y: root.mixPos(root.middlePackedY, root.middleSpreadY)
    }

    RailLane {
        id: bottomZone
        ids: root.rightIds
        x: root.islandPad
        width: Math.max(0, root.width - root.islandPad * 2)
        height: implicitHeight
        y: root.mixPos(root.bottomPackedY, root.bottomSpreadY)
    }

    Item {
        id: leftIslandHit
        visible: root.islands && topZone.height > 0
        x: 0; y: Math.max(0, topZone.y - root.islandPad); width: root.width
        height: Math.min(root.height - y, topZone.height + root.islandPad * 2)
    }
    Item {
        id: centerIslandHit
        visible: root.islands && middleZone.height > 0
        x: 0; width: root.width
        y: Math.max(0, middleZone.y - root.islandPad)
        height: Math.min(root.height - y, middleZone.height + root.islandPad * 2)
    }
    Item {
        id: rightIslandHit
        visible: root.islands && bottomZone.height > 0
        x: 0; width: root.width
        y: Math.max(0, bottomZone.y - root.islandPad)
        height: Math.min(root.height - y, bottomZone.height + root.islandPad * 2)
    }

    property alias leftIslandRegion: leftIslandHit
    property alias centerIslandRegion: centerIslandHit
    property alias rightIslandRegion: rightIslandHit

    Repeater {
        model: root.islands ? [leftIslandHit, centerIslandHit, rightIslandHit] : []
        delegate: Rectangle {
            required property var modelData
            x: modelData.x; y: modelData.y; width: modelData.width; height: modelData.height
            visible: modelData.visible && modelData.height > 0
            radius: root.corner
            color: root.pal.alpha(root.pal.paper, root.pal.barOpacity)
            border.width: root.pal.borderWidth
            border.color: root.pal.alpha(root.pal.line, root.pal.borderOpacity)
            antialiasing: true
            z: -1
        }
    }

    // Vertical progress rides one edge of the chosen lane/island. Automatic mode
    // chooses the middle island in Islands and the whole rail in Strip.
    Item {
        id: progress
        readonly property string mode: root.pal.indicatorMode
        readonly property bool daily: mode === "daily"
        readonly property bool known: root.media !== null && root.media.hasLength === true
        readonly property real fraction: daily ? HD.dayFraction(root.now)
            : (known ? HD.clamp01(root.media.progress) : 0)
        readonly property string placement: root.pal.progressPlacement === "auto"
            ? (root.islands ? "center" : "whole") : root.pal.progressPlacement
        readonly property Item target: placement === "left" ? leftIslandHit
            : placement === "center" ? centerIslandHit
            : placement === "right" ? rightIslandHit : null
        readonly property int thick: root.px(root.pal.progressThickness)
        x: root.pal.edge === "left" ? root.width - Math.max(2, thick) : 0
        y: target ? target.y : 0
        width: Math.max(2, thick)
        height: target ? target.height : root.height
        visible: mode !== "disabled" && root.pal.progressStyle !== "none"
            && placement !== "module" && height > 0

        readonly property bool hairline: root.pal.progressStyle === "hairline"
        readonly property color trackColor: hairline ? root.pal.progressHairline : root.pal.progressTrack
        readonly property color fillColor: root.pal.progressStyle === "accent" ? root.pal.progress : root.pal.progressSoft

        // The empty rod fades out at both the top and the bottom end.
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(progress.trackColor.r, progress.trackColor.g, progress.trackColor.b, 0) }
                GradientStop { position: 0.06; color: progress.trackColor }
                GradientStop { position: 0.94; color: progress.trackColor }
                GradientStop { position: 1; color: Qt.rgba(progress.trackColor.r, progress.trackColor.g, progress.trackColor.b, 0) }
            }
        }
        // The spent part fades in from the start.
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: Math.round(parent.height * progress.fraction)
            radius: width / 2
            opacity: root.pal.progressOpacity
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: Qt.rgba(progress.fillColor.r, progress.fillColor.g, progress.fillColor.b, 0) }
                GradientStop { position: 0.35; color: Qt.rgba(progress.fillColor.r, progress.fillColor.g, progress.fillColor.b, 0.35) }
                GradientStop { position: 1; color: progress.fillColor }
            }
        }
        // Hour marks point into the rail, start to end. They belong to the day alone.
        Repeater {
            model: HD.hourTicks()
            Rectangle {
                id: vtick
                required property var modelData
                readonly property real len: root.px(modelData.major ? 5 : 3)
                y: HD.at(modelData.fraction, progress.height, 1)
                x: root.pal.edge === "left" ? -len : progress.width
                width: len
                height: 1
                color: modelData.fraction <= HD.dayFraction(root.now) ? root.pal.progressTick : root.pal.progressTickDim
                opacity: progress.daily ? root.pal.progressOpacity : 0
            }
        }
    }

    component RailLane: Column {
        id: lane
        required property var ids
        height: implicitHeight
        spacing: root.gap
        Repeater {
            model: lane.ids
            delegate: RailCell {
                required property string modelData
                moduleId: modelData
                width: lane.width
            }
        }
    }

    component RailCell: Item {
        id: cell
        required property string moduleId
        readonly property string treatment: root.moduleStyle(moduleId)
        readonly property var options: root.pal.moduleOptions(moduleId)
        readonly property real moduleScale: options.scale
        readonly property int pad: (treatment === "plain" ? 0 : root.px(5)) + root.px(options.padding)
        readonly property bool shown: loader.item ? loader.item.shown === true : false
        width: root.width - root.islandPad * 2
        height: shown ? loader.height * moduleScale + pad * 2 : 0
        visible: height > 0
        opacity: (treatment === "ghost" ? 0.52 : 1) * options.opacity

        Rectangle {
            anchors.fill: parent
            visible: treatment !== "plain" && treatment !== "ghost" && cell.shown
            radius: Math.min(root.innerCorner, width / 2, height / 2)
            color: root.styleFill(cell.moduleId)
            border.width: treatment === "outline" || treatment === "paper" || treatment === "accent" ? root.pal.borderWidth : 0
            border.color: root.styleBorder(cell.moduleId)
        }
        Loader {
            id: loader
            anchors.horizontalCenter: parent.horizontalCenter
            y: cell.pad + (height * cell.moduleScale - height) / 2
            width: Math.max(0, cell.width - cell.pad * 2)
            height: item ? item.implicitHeight : 0
            scale: cell.moduleScale
            transformOrigin: Item.Center
            sourceComponent: root.moduleComponent(cell.moduleId)
            onLoaded: if (item && "moduleId" in item) item.moduleId = cell.moduleId
        }
    }

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

    Component {
        id: cClock
        Item {
            property string moduleId: "clock"
            readonly property bool shown: root.pal.showTime || root.pal.showDate
            implicitHeight: shown ? clockCol.implicitHeight + root.px(6) : 0
            width: parent ? parent.width : root.width
            Column {
                id: clockCol
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                Text {
                    visible: root.pal.showTime
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(root.now, root.pal.hours === "24h" ? "HH:mm" : "h:mm")
                    color: root.pal.ink
                    font.family: root.pal.display
                    font.pixelSize: Math.max(root.valuePx, Math.round(root.px(16) * root.pal.textScale))
                }
                Text {
                    visible: root.pal.showDate
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(root.now, Schema.splitDate(root.pal.dateFormat).top).toUpperCase()
                    color: root.pal.inkMuted
                    font.family: root.pal.mono
                    font.pixelSize: root.labelPx
                }
                Rectangle {
                    visible: root.pal.indicatorMode === "daily" && root.pal.progressPlacement === "module"
                        && root.pal.progressStyle !== "none"
                    width: Math.max(root.px(24), clockCol.width)
                    height: Math.max(1, root.px(root.pal.progressThickness))
                    radius: height / 2
                    id: dayBar
                    readonly property color trackColor: root.pal.progressStyle === "hairline" ? root.pal.progressHairline : root.pal.progressTrack
                    readonly property color fillColor: root.pal.progressStyle === "accent" ? root.pal.progress : root.pal.progressSoft
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(dayBar.trackColor.r, dayBar.trackColor.g, dayBar.trackColor.b, 0) }
                        GradientStop { position: 0.06; color: dayBar.trackColor }
                        GradientStop { position: 0.94; color: dayBar.trackColor }
                        GradientStop { position: 1; color: Qt.rgba(dayBar.trackColor.r, dayBar.trackColor.g, dayBar.trackColor.b, 0) }
                    }
                    Rectangle {
                        width: parent.width * HD.dayFraction(root.now)
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
                            x: HD.at(modelData.fraction, dayBar.width, 1)
                            y: -height
                            width: 1
                            height: root.px(modelData.major ? 5 : 3)
                            color: modelData.fraction <= HD.dayFraction(root.now) ? root.pal.progressTick : root.pal.progressTickDim
                            opacity: root.pal.progressOpacity
                        }
                    }
                }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.clockClicked() }
        }
    }

    Component {
        id: cWorkspaces
        Item {
            readonly property bool shown: root.spaces.length > 0
            implicitHeight: shown ? wsCol.implicitHeight : 0
            width: parent ? parent.width : root.width
            Column {
                id: wsCol
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.px(3)
                Repeater {
                    model: root.spaces
                    delegate: Rectangle {
                        id: ws
                        required property var modelData
                        readonly property bool liveWs: String(modelData.id) === root.activeWorkspace
                        width: root.px(24); height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: root.controlRadius(width, height)
                        color: liveWs ? root.pal.bone : "transparent"
                        border.width: liveWs ? 0 : 1
                        border.color: root.pal.line
                        Text {
                            anchors.centerIn: parent
                            text: Schema.workspaceText(root.pal.workspaceStyle, String(ws.modelData.id), String(ws.modelData.kanji || ws.modelData.name || ws.modelData.id))
                            color: ws.liveWs ? root.pal.boneInk : root.pal.inkDim
                            font.family: root.pal.workspaceStyle === "kanji" ? root.pal.jp : root.pal.text
                            font.pixelSize: root.labelPx
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.workspaceActivated(String(ws.modelData.id)) }
                    }
                }
            }
        }
    }

    Component {
        id: cTitle
        Item {
            readonly property string label: root.appClass.length ? root.appClass : root.windowTitle
            readonly property bool shown: label.length > 0
            implicitHeight: shown ? root.px(34) : 0
            width: parent ? parent.width : root.width
            Text {
                anchors.centerIn: parent
                width: parent.width - root.px(6)
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: parent.label
                color: root.pal.inkDim
                font.family: root.pal.text
                font.pixelSize: root.labelPx
            }
        }
    }

    Component {
        id: cMedia
        // सबसे छोटी बिट में निशान है; आठ निशान मिलकर एक अक्षर बनाते हैं।
        // ↑┌ ’ ┤• / ┘ ∨ ∨ ∧ ┤• ┌ ┼• ┐ / ┌ ‹ / ∨• ┘ ∨ / ├• ┼• └• ∧• / ∧• ├• ∧ , / ┼• ┼ ∧ ┌• 0 , / ∨• ┬ ├• / ├ ├• ∧ ┼• ┤ / ‹ ┬ ┌ ∨ .
        Item {
            readonly property bool shown: root.media !== null
            implicitHeight: shown ? root.px(46) : 0
            width: parent ? parent.width : root.width
            Column {
                anchors.centerIn: parent
                width: parent.width - root.px(8)
                spacing: root.px(3)
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: root.media ? String(root.media.title || "Media") : ""
                    color: root.media && root.media.playing ? root.pal.ink : root.pal.inkDim
                    font.family: root.pal.display
                    font.italic: true
                    font.pixelSize: root.labelPx
                }
                Rectangle {
                    visible: root.pal.indicatorMode === "music" && root.pal.progressPlacement === "module" && root.pal.progressStyle !== "none"
                    width: parent.width; height: Math.max(1, root.px(root.pal.progressThickness)); radius: height / 2
                    id: musicBar
                    readonly property color trackColor: root.pal.progressStyle === "hairline" ? root.pal.progressHairline : root.pal.progressTrack
                    readonly property color fillColor: root.pal.progressStyle === "accent" ? root.pal.progress : root.pal.progressSoft
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(musicBar.trackColor.r, musicBar.trackColor.g, musicBar.trackColor.b, 0) }
                        GradientStop { position: 0.06; color: musicBar.trackColor }
                        GradientStop { position: 0.94; color: musicBar.trackColor }
                        GradientStop { position: 1; color: Qt.rgba(musicBar.trackColor.r, musicBar.trackColor.g, musicBar.trackColor.b, 0) }
                    }
                    Rectangle {
                        width: parent.width * (root.media ? HD.clamp01(root.media.progress) : 0)
                        height: parent.height; radius: height / 2
                        opacity: root.pal.progressOpacity
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.rgba(musicBar.fillColor.r, musicBar.fillColor.g, musicBar.fillColor.b, 0) }
                            GradientStop { position: 0.35; color: Qt.rgba(musicBar.fillColor.r, musicBar.fillColor.g, musicBar.fillColor.b, 0.35) }
                            GradientStop { position: 1; color: musicBar.fillColor }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: mouse => root.mediaAction(mouse.button === Qt.MiddleButton ? "next" : "open")
                onWheel: wheel => root.mediaAction(wheel.angleDelta.y > 0 ? "previous" : "next")
            }
        }
    }

    Component {
        id: cStatus
        Item {
            readonly property var rows: {
                const out = []
                if (root.network) out.push({ key: "network", glyph: root.network.kind === "wifi" ? "網" : "線", value: root.network.off ? "×" : String(root.network.name || "ON").slice(0, 3) })
                if (root.volume) out.push({ key: "volume", glyph: "音", value: root.volume.muted ? "×" : String(root.volume.percent) })
                if (root.battery) out.push({ key: "battery", glyph: "充", value: String(root.battery.percent) })
                if (root.brightness) out.push({ key: "brightness", glyph: "光", value: String(root.brightness.percent) })
                return out
            }
            readonly property bool shown: rows.length > 0
            implicitHeight: shown ? stCol.implicitHeight : 0
            width: parent ? parent.width : root.width
            Column {
                id: stCol
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.px(3)
                Repeater {
                    model: parent.parent.rows
                    delegate: Rectangle {
                        id: st
                        required property var modelData
                        width: root.width - root.islandPad * 2 - root.px(8)
                        height: root.px(24)
                        radius: root.controlRadius(width, height)
                        color: hover.hovered ? root.pal.hover : "transparent"
                        Row {
                            anchors.centerIn: parent
                            spacing: root.px(4)
                            Text { text: st.modelData.glyph; color: root.pal.inkMuted; font.family: root.pal.jp; font.pixelSize: root.labelPx }
                            Text { text: st.modelData.value; color: root.pal.ink; font.family: root.pal.text; font.pixelSize: root.labelPx }
                        }
                        HoverHandler { id: hover }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => root.statusAction(st.modelData.key, mouse.button === Qt.RightButton ? "right" : (mouse.button === Qt.MiddleButton ? "middle" : "click"))
                            onWheel: wheel => root.statusAction(st.modelData.key, wheel.angleDelta.y > 0 ? "up" : "down")
                        }
                    }
                }
            }
        }
    }

    Component {
        id: cIndicators
        Item {
            readonly property bool shown: root.indicators.length > 0
            implicitHeight: shown ? indCol.implicitHeight : 0
            width: parent ? parent.width : root.width
            Column {
                id: indCol
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.px(4)
                Repeater {
                    model: root.indicators
                    delegate: Rectangle {
                        id: ind
                        required property var modelData
                        width: root.px(22); height: width
                        anchors.horizontalCenter: parent.horizontalCenter
                        radius: root.controlRadius(width, height)
                        color: modelData.red ? root.pal.seal : root.pal.bone
                        Text { anchors.centerIn: parent; text: ind.modelData.glyph; color: ind.modelData.red ? root.pal.onSeal : root.pal.boneInk; font.family: root.pal.jp; font.pixelSize: root.labelPx }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.indicatorAction(String(ind.modelData.key), "click") }
                    }
                }
            }
        }
    }

    Component {
        id: cInbox
        Item {
            readonly property bool shown: root.notifications.length > 0
            implicitHeight: shown ? root.px(32) : 0
            width: parent ? parent.width : root.width
            Rectangle {
                anchors.centerIn: parent
                width: root.px(28); height: root.px(24)
                radius: root.controlRadius(width, height)
                color: root.notifications.length ? root.pal.sealTint : "transparent"
                Text { anchors.centerIn: parent; text: "報 " + String(root.notifications.length); color: root.pal.ink; font.family: root.pal.jp; font.pixelSize: root.labelPx }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.inboxAction("click") }
        }
    }

    Component {
        id: cTray
        KarumaTray {
            pal: root.pal
            unit: root.k
            innerCorner: root.innerCorner
            live: root.pal.animate
            vertical: true
            edge: root.pal.edge
        }
    }

    Component {
        id: cQuick
        Item {
            readonly property bool shown: true
            implicitHeight: root.px(32)
            width: parent ? parent.width : root.width
            Rectangle {
                anchors.centerIn: parent
                width: root.px(26); height: width
                radius: root.controlRadius(width, height)
                color: root.quickOpen ? root.pal.bone : "transparent"
                border.width: root.pal.borderWidth
                border.color: root.quickOpen ? root.pal.bone : root.pal.line
                Text { anchors.centerIn: parent; text: "設"; color: root.quickOpen ? root.pal.boneInk : root.pal.inkMuted; font.family: root.pal.jp; font.pixelSize: root.labelPx }
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.quickClicked() }
        }
    }

    Component {
        id: cRyokuPlugin
        Item {
            id: pluginView
            property string moduleId: ""
            readonly property string pid: root.pluginId(moduleId)
            readonly property var entry: root.pluginHost ? root.pluginHost.entryFor(pid) : null
            readonly property bool shown: !!entry && root.pluginHost && root.pluginHost.isEnabled(pid)
            readonly property string versionQuery: entry && entry.version ? "?v=" + encodeURIComponent(entry.version) : ""
            readonly property string stateRoot: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/plugins/" + pid
            implicitHeight: shown && contentSlot.item ? Math.max(root.px(28), contentSlot.item.implicitHeight + root.px(6)) : 0
            width: parent ? parent.width : root.width

            property var api: QtObject {
                readonly property var mainInstance: serviceSlot.item
                readonly property var pluginSettings: (pluginView.entry && pluginView.entry.placement && pluginView.entry.placement.settings) ? pluginView.entry.placement.settings : ({})
                readonly property string pluginDir: pluginView.entry ? pluginView.entry.dir : ""
                readonly property string stateDir: pluginView.stateRoot
                readonly property bool panelOpen: root.activePluginPanelId === pluginView.pid
                readonly property bool hasPanel: !!(pluginView.entry && pluginView.entry.manifest && pluginView.entry.manifest.entryPoints && pluginView.entry.manifest.entryPoints.panel)
                function saveSetting(key, value) { if (root.pluginHost) root.pluginHost.saveSetting(pluginView.pid, key, value) }
                function saveSettings() {}
                function openPanel() { if (hasPanel) root.pluginPanelRequested(pluginView.pid, this) }
                function closePanel() { if (panelOpen) root.pluginPanelRequested("", this) }
                function togglePanel() { root.pluginPanelRequested(panelOpen ? "" : pluginView.pid, this) }
                Component.onCompleted: if (stateDir.length) Quickshell.execDetached(["mkdir", "-p", stateDir])
            }

            PluginObjectSlot {
                id: serviceSlot
                source: pluginView.entry ? "file://" + pluginView.entry.dir + "/service/Main.qml" + pluginView.versionQuery : ""
                configure: service => { if (service && "pluginApi" in service) service.pluginApi = pluginView.api }
            }
            PluginObjectSlot {
                id: contentSlot
                anchors.centerIn: parent
                width: item ? Math.min(item.implicitWidth, pluginView.width - root.px(6)) : 0
                height: item ? item.implicitHeight : 0
                source: pluginView.entry ? "file://" + pluginView.entry.dir + "/content/Widget.qml" + pluginView.versionQuery : ""
                configure: content => {
                    if (!content) return
                    if ("pluginApi" in content) content.pluginApi = pluginView.api
                    if ("density" in content) content.density = "glyph"
                    if ("widthBudget" in content) content.widthBudget = Math.max(24, pluginView.width - root.px(8))
                    if ("active" in content) content.active = true
                }
            }
        }
    }
}
