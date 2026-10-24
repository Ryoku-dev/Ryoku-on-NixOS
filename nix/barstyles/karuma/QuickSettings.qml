pragma ComponentBehavior: Bound

import QtQuick

/*
 * The quick settings menu: everyday desktop controls in one small sheet.
 *
 * Pure QtQuick, like BarSurface: plain data in, signals out (Scene.qml feeds it
 * live system state and applies each change straight away). A control is drawn
 * only when it is switched on in the hub (`hiddenKey` lists the ones that are
 * off) and the machine actually has the thing behind it: its data is null
 * otherwise (no backlight on a desktop, no Bluetooth adapter, no microphone), so
 * nothing in here is ever a dead control.
 *
 *   volume      slider + mute        { percent, level, muted }
 *   brightness  slider               { percent }
 *   wifi        tile                 { on, name }
 *   bluetooth   tile                 { on, name }
 *   mic         tile                 { muted }
 *   awake       tile                 keepAwake
 *
 * It follows the strip's paper-and-ink look (KarumaPalette) and shares PopupHeader,
 * LevelRow and PaperButton with the other sheets. It is for everyday controls; configuring Karuma itself stays in
 * the hub.
 */
Item {
    id: root

    required property var pal
    // The screen's UI scale (what the other pop-up sheets use), not the bar size.
    property real k: 1
    property string hiddenKey: ""

    property var volume: null
    property var brightness: null
    property var wifi: null
    property var bluetooth: null
    property var mic: null
    property bool keepAwake: false

    signal volumeSet(real level)
    signal volumeMute()
    signal brightnessSet(real percent)
    signal wifiToggle()
    signal bluetoothToggle()
    signal micToggle()
    signal awakeToggle()

    function px(v) { return Math.round(v * root.k) }

    readonly property var off: hiddenKey.length ? hiddenKey.split(",") : []
    function wants(id) { return root.off.indexOf(id) < 0; }

    readonly property bool showVolume: wants("volume") && volume !== null
    readonly property bool showBrightness: wants("brightness") && brightness !== null
    readonly property bool showWifi: wants("wifi") && wifi !== null
    readonly property bool showBluetooth: wants("bluetooth") && bluetooth !== null
    readonly property bool showMic: wants("mic") && mic !== null
    readonly property bool showAwake: wants("awake")
    readonly property bool anySlider: showVolume || showBrightness
    readonly property bool anyTile: showWifi || showBluetooth || showMic || showAwake

    width: parent ? parent.width : px(300)
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width
        spacing: root.px(14)

        PopupHeader {
            pal: root.pal
            k: root.k
            glyph: "設"
            title: "Quick settings"
            eyebrow: "KARUMA · EVERYDAY CONTROLS"
            closable: false
        }

        // Levels sit together on one raised card.
        Rectangle {
            visible: root.anySlider
            width: parent.width
            implicitHeight: levels.implicitHeight + 2 * root.px(10)
            height: implicitHeight
            radius: root.px(root.pal.radiusM)
            color: root.pal.raised
            border.width: 1
            border.color: root.pal.lineSoft

            Column {
                id: levels
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.px(10) }
                spacing: root.px(4)

                LevelRow {
                    pal: root.pal
                    k: root.k
                    visible: root.showVolume
                    glyph: "耳"
                    glyphIsButton: true
                    level: root.volume ? root.volume.level : 0
                    urgent: root.volume ? !!root.volume.muted : false
                    readout: root.volume ? (root.volume.muted ? "MUTE" : root.volume.percent + "%") : ""
                    onMoved: (v) => root.volumeSet(v)
                    onGlyphClicked: root.volumeMute()
                }

                LevelRow {
                    pal: root.pal
                    k: root.k
                    visible: root.showBrightness
                    glyph: "光"
                    // Never all the way to black: 1% is the floor the slider can reach.
                    minLevel: 0.01
                    level: root.brightness ? root.brightness.percent / 100 : 0
                    readout: root.brightness ? root.brightness.percent + "%" : ""
                    onMoved: (v) => root.brightnessSet(Math.round(v * 100))
                }
            }
        }

        Flow {
            id: tiles
            visible: root.anyTile
            width: parent.width
            spacing: root.px(8)
            readonly property real cell: Math.floor((width - spacing) / 2)

            PaperButton {
                visible: root.showWifi
                pal: root.pal
                uiScale: root.k
                width: tiles.cell
                glyph: "網"
                label: "WI-FI"
                detail: root.wifi ? (root.wifi.on ? (root.wifi.name || "On") : "Off") : ""
                selected: root.wifi ? root.wifi.on : false
                onActivated: root.wifiToggle()
            }
            PaperButton {
                visible: root.showBluetooth
                pal: root.pal
                uiScale: root.k
                width: tiles.cell
                glyph: "双"
                label: "BLUETOOTH"
                detail: root.bluetooth ? (root.bluetooth.on ? (root.bluetooth.name || "On") : "Off") : ""
                selected: root.bluetooth ? root.bluetooth.on : false
                onActivated: root.bluetoothToggle()
            }
            PaperButton {
                visible: root.showMic
                pal: root.pal
                uiScale: root.k
                width: tiles.cell
                glyph: "声"
                label: "MICROPHONE"
                detail: root.mic ? (root.mic.muted ? "Muted" : "Live") : ""
                selected: root.mic ? !root.mic.muted : false
                onActivated: root.micToggle()
            }
            PaperButton {
                visible: root.showAwake
                pal: root.pal
                uiScale: root.k
                width: tiles.cell
                glyph: "目"
                label: "STAY AWAKE"
                detail: root.keepAwake ? "On" : "Off"
                selected: root.keepAwake
                onActivated: root.awakeToggle()
            }
        }

        Text {
            visible: !root.anySlider && !root.anyTile
            width: parent.width
            text: "Nothing to show. Turn controls on under Quick settings in Karuma's hub."
            color: root.pal.inkMuted
            font.family: root.pal.text
            font.pixelSize: root.px(12)
            wrapMode: Text.WordWrap
        }
    }
}
