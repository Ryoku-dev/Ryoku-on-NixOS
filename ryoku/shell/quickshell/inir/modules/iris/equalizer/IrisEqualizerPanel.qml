pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import shell.services as Ryoku
import inir
import inir.services
import inir.modules.common
import inir.modules.common.widgets
import inir.modules.iris.components
import inir.modules.iris.style

PanelWindow {
    id: root

    property bool open: false
    property string targetOutput: ""
    signal closeRequested()

    readonly property real d: IrisStyle.density
    readonly property real safePadding: Math.max(12, Math.round(Math.min(screen?.width ?? 1920, screen?.height ?? 1080) * 0.02))
    readonly property real panelWidth: Math.round(Math.max(360, Math.min(880, (screen?.width ?? 1920) - root.safePadding * 2, (screen?.width ?? 1920) * 0.48)))
    readonly property real panelPadding: IrisStyle.concentricPad(IrisStyle.surfaceRadius("settings", IrisStyle.radiusPanel), 16 * root.d)
    readonly property real panelMaxHeight: Math.min(760, Math.max(1, (screen?.height ?? 1080) - root.safePadding * 2))
    readonly property real panelHeight: Math.round(Math.min(root.panelMaxHeight,
        root.panelPadding * 2 + headerRow.implicitHeight + contentColumn.spacing
            + sections.implicitHeight + Math.round(8 * root.d)))
    readonly property string headline: !Ryoku.Equalizer.on
        ? Translation.tr("Bypassed · %1").arg(Ryoku.Equalizer.presetLabel(Ryoku.Equalizer.preset))
        : Ryoku.Equalizer.running
            ? Translation.tr("%1 · shaping this output").arg(Ryoku.Equalizer.presetLabel(Ryoku.Equalizer.preset))
            : Translation.tr("%1 · starting the audio graph").arg(Ryoku.Equalizer.presetLabel(Ryoku.Equalizer.preset))

    onOpenChanged: if (root.open) Ryoku.Equalizer.refresh()

    visible: root.open || frame.progress > 0
    color: "transparent"
    anchors { left: true; right: true; top: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:shima-equalizer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: (!root.open || !frame.armed) ? frame : dismissArea }

    IrisOutputHold {
        id: outputHold
        wanted: Quickshell.screens.find(output => output.name === root.targetOutput)
            ?? GlobalStates.focusedScreen
        live: root.visible
    }
    screen: outputHold.output

    Shortcut {
        sequence: "Escape"
        enabled: root.open
        onActivated: root.closeRequested()
    }

    MouseArea {
        id: dismissArea
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    IrisMorphSurface {
        id: frame
        objectName: "shimaEqualizerFrame"
        open: root.open
        motionSurface: "settings"
        radius: IrisStyle.surfaceRadius("settings", IrisStyle.radiusPanel)
        light: IrisStyle.surfaceLight("settings", IrisStyle.wallpaperLight)
        x: parent.width - width - root.safePadding
        y: Math.round((parent.height - height) / 2)
        width: root.panelWidth
        height: root.panelHeight

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: root.panelPadding
            spacing: Math.round(12 * root.d)

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Math.round(8 * root.d)

                IrisMark { implicitSize: Math.round(24 * root.d) }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    IrisText {
                        text: Translation.tr("Shima Equalizer")
                        font.family: IrisStyle.fontTitle
                        font.pixelSize: IrisStyle.typeTitle
                        font.weight: IrisStyle.weight(Font.Bold)
                    }
                    IrisText {
                        Layout.fillWidth: true
                        text: root.headline
                        color: Ryoku.Equalizer.on ? IrisStyle.muted : IrisStyle.textSecondary
                        font.pixelSize: IrisStyle.typeFootnote
                        elide: Text.ElideRight
                    }
                }
                IrisButton {
                    text: Ryoku.Equalizer.on ? Translation.tr("On") : Translation.tr("Off")
                    emphasized: Ryoku.Equalizer.on
                    quiet: !Ryoku.Equalizer.on
                    buttonRadius: height / 2
                    Accessible.name: Ryoku.Equalizer.on
                        ? Translation.tr("Bypass equalizer") : Translation.tr("Turn on equalizer")
                    onClicked: Ryoku.Equalizer.setOn(!Ryoku.Equalizer.on)
                }
                IrisIconButton {
                    materialIcon: "refresh"
                    Accessible.name: Translation.tr("Refresh equalizer")
                    onClicked: Ryoku.Equalizer.refresh()
                }
                IrisIconButton {
                    materialIcon: "close"
                    Accessible.name: Translation.tr("Close equalizer")
                    onClicked: root.closeRequested()
                }
            }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: sections.implicitHeight + Math.round(8 * root.d)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: IrisScrollBar {}

                ColumnLayout {
                    id: sections
                    width: flick.width
                    spacing: Math.round(16 * root.d)

                    IrisEqPresets { Layout.fillWidth: true }
                    IrisEqBands { Layout.fillWidth: true }

                    IrisText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: Math.round(4 * root.d)
                        text: Translation.tr("Drag a band, use the wheel or arrow keys, or double-click it to return that band to zero.")
                        color: IrisStyle.muted
                        font.pixelSize: IrisStyle.typeFootnote
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
