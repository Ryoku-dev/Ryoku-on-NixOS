import QtQuick
import QtQuick.Layouts
import Quickshell
import stage.modules.common.widgets
import stage.services
import shell.modules.phone as Phone
import Ryoku.Ui as Ui
import "../clock"
import stage.modules.common.functions
import ".."

/**
 * Where dropped files go: KDE Connect or LocalSend, and which device. Picking
 * a device sends the files waiting from an earlier drop.
 */
ColumnLayout {
    id: panel

    property var host: null
    readonly property var tile: panel.host?.tile ?? null
    readonly property var cfg: Config.options.dock.utilities.send
    readonly property bool localSend: panel.cfg.backend === "localsend"
    readonly property var pending: panel.tile?.pending ?? []
    readonly property var kdeDevices: (Phone.KdeConnectService.devices ?? []).filter(device => device.paired)
    property bool ownsScan: false

    spacing: 8

    function chooseKde(device) {
        panel.cfg.kdeDevice = device.id;
        if (panel.pending.length > 0 && device.reachable)
            Qt.callLater(() => panel.tile?.send(panel.pending));
    }
    function chooseLocal(device) {
        panel.cfg.localsendAlias = String(device.alias ?? device.name ?? device.ip);
        panel.cfg.localsendIp = String(device.ip);
        if (panel.pending.length > 0)
            Qt.callLater(() => panel.tile?.send(panel.pending));
    }

    function startScan() {
        if (!LocalSend.available)
            return;
        panel.ownsScan = true;
        LocalSend.startScanning();
    }
    function syncScanning() {
        if (panel.localSend && LocalSend.available) {
            if (!LocalSend.scanning)
                panel.startScan();
        } else if (panel.ownsScan) {
            if (LocalSend.scanning)
                LocalSend.stopScanning();
            panel.ownsScan = false;
        }
    }
    Component.onCompleted: panel.syncScanning()
    onLocalSendChanged: panel.syncScanning()
    Connections {
        target: LocalSend
        function onAvailableChanged() { panel.syncScanning(); }
        function onScanningChanged() {
            if (!LocalSend.scanning)
                panel.ownsScan = false;
        }
    }
    Component.onDestruction: {
        if (panel.ownsScan && LocalSend.scanning)
            LocalSend.stopScanning();
        panel.ownsScan = false;
    }

    // ── Waiting files ───────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        visible: panel.pending.length > 0
        implicitHeight: 52
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colTertiaryContainer
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 8
            MaterialSymbol {
                text: "schedule_send"
                iconSize: 20
                color: ClockStyle.colOnTertiaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: panel.pending.length === 1
                    ? Translation.tr("1 file waiting · pick a device")
                    : Translation.tr("%1 files waiting · pick a device").arg(panel.pending.length)
                color: ClockStyle.colOnTertiaryContainer
                font.pixelSize: ClockStyle.textNormal
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            ClockCardAction {
                symbol: "close"
                tip: Translation.tr("Discard")
                colContent: ClockStyle.colOnTertiaryContainer
                onClicked: panel.tile.pending = []
            }
        }
    }

    // ── Backend ─────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                { id: "kdeconnect", label: "KDE Connect", symbol: "smartphone" },
                { id: "localsend", label: "LocalSend", symbol: "near_me" }
            ]
            delegate: ClockChip {
                required property var modelData
                Layout.fillWidth: true
                label: modelData.label
                symbol: modelData.symbol
                selected: panel.cfg.backend === modelData.id
                onClicked: panel.cfg.backend = modelData.id
            }
        }
    }

    // ── Devices ─────────────────────────────────────────────────────────
    component DeviceRow: Rectangle {
        id: row
        property string name
        property string detail
        property string symbol
        property bool chosen
        property bool online: true
        property bool first
        signal picked()
        Layout.fillWidth: true
        implicitHeight: 56
        radius: row.first ? ClockStyle.radiusNormal : ClockStyle.radiusSmall
        color: row.chosen ? ClockStyle.colSecondaryContainer : (rowHover.hovered ? ClockStyle.colFieldHover : ClockStyle.colField)
        opacity: row.online ? 1 : 0.6
        HoverHandler {
            id: rowHover
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: row.picked()
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 14
            spacing: 10
            MaterialShapeWrappedMaterialSymbol {
                text: row.symbol
                iconSize: 18
                padding: 8
                shape: row.chosen ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Circle
                color: row.chosen ? ClockStyle.colPrimary : ClockStyle.colSurfaceHighest
                colSymbol: row.chosen ? ClockStyle.colOnPrimary : ClockStyle.colOnSurface
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.name
                    color: row.chosen ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textNormal
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.detail
                    color: row.chosen ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    opacity: 0.8
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }
            }
            MaterialSymbol {
                visible: row.chosen
                text: "check"
                iconSize: 18
                color: ClockStyle.colOnSecondaryContainer
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: !panel.localSend
        spacing: 3
        Repeater {
            model: panel.kdeDevices
            delegate: DeviceRow {
                required property var modelData
                required property int index
                first: index === 0
                name: modelData.name
                detail: modelData.reachable
                    ? (modelData.charge >= 0 ? Translation.tr("Online · %1%").arg(modelData.charge) : Translation.tr("Online"))
                    : Translation.tr("Offline")
                symbol: modelData.type === "tablet" ? "tablet_android" : modelData.type === "desktop" ? "computer" : "smartphone"
                online: modelData.reachable
                chosen: (panel.tile?.kdeDeviceId ?? "") === modelData.id
                onPicked: panel.chooseKde(modelData)
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.margins: 6
            visible: panel.kdeDevices.length === 0
            text: Phone.KdeConnectService.available ? Translation.tr("No paired devices. Pair one in KDE Connect.")
                : Translation.tr("KDE Connect is not running")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: panel.localSend
        spacing: 3
        Repeater {
            model: LocalSend.discoveredDevices
            delegate: DeviceRow {
                required property var modelData
                required property int index
                first: index === 0
                name: String(modelData.alias ?? modelData.name ?? modelData.ip)
                detail: String(modelData.ip ?? "")
                symbol: modelData.type === "mobile" ? "smartphone" : "computer"
                chosen: (panel.cfg.localsendIp ?? "") === String(modelData.ip)
                onPicked: panel.chooseLocal(modelData)
            }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.margins: 6
            visible: LocalSend.discoveredDevices.length === 0
            text: !LocalSend.available ? Translation.tr("LocalSend is not installed.")
                : LocalSend.pyteChecked && !LocalSend.pyteAvailable ? Translation.tr("LocalSend needs the Python pyte package before it can send files.")
                : LocalSend.scanning ? Translation.tr("Looking for devices…")
                : panel.cfg.localsendAlias ? Translation.tr("Last used: %1").arg(panel.cfg.localsendAlias)
                : Translation.tr("No devices found")
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textNormal
            wrapMode: Text.WordWrap
        }
        StyledText {
            Layout.fillWidth: true
            Layout.margins: 6
            visible: LocalSend.installError.length > 0
            text: LocalSend.installError
            color: ClockStyle.colError
            font.pixelSize: ClockStyle.textSmall
            wrapMode: Text.WordWrap
        }
        ClockButton {
            Layout.fillWidth: true
            visible: !LocalSend.available
            enabled: !LocalSend.installing
            symbol: "download"
            label: LocalSend.installing ? Translation.tr("Installing…") : Translation.tr("Install LocalSend")
            onClicked: LocalSend.installOfficialCli()
        }
        ClockButton {
            Layout.fillWidth: true
            enabled: LocalSend.available && !LocalSend.scanning
            symbol: "radar"
            label: LocalSend.scanning ? Translation.tr("Scanning…") : Translation.tr("Scan again")
            onClicked: panel.startScan()
        }
    }
    ClockButton {
        Layout.fillWidth: true
        visible: panel.tile?.ready ?? false
        symbol: "attach_file"
        label: Translation.tr("Choose a file…")
        onClicked: sendPicker.open()
    }
    Ui.FileDialogHost {
        id: sendPicker
        title: panel.localSend ? Translation.tr("Send a file with LocalSend") : Translation.tr("Send a file to phone")
        currentFolder: "file://" + FileUtils.trimFileProtocol(Directories.home)
        onAccepted: {
            const path = UtilityFiles.pathFromUrl(selectedFile);
            if (path.length > 0)
                panel.tile?.send([path]);
            panel.host?.closePanel();
        }
    }
}
