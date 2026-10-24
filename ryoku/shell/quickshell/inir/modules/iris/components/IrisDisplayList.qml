pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import inir
import inir.services
import inir.modules.common
import inir.modules.common.models.quickToggles
import inir.modules.common.widgets
import inir.modules.iris.style

// The Control Center's Display expansion: this screen's brightness, Night Light with its warmth and schedule,
// dark mode and soft flashes.
ColumnLayout {
    id: root

    property var targetScreen: null
    readonly property real d: IrisStyle.density
    readonly property var monitor: Brightness.getMonitorForScreen(root.targetScreen)
    readonly property real brightness: Number(root.monitor?.brightness ?? Number.NaN)
    readonly property int warmth: Nightlight.temperature
    spacing: 2 * root.d

    NightLightToggle { id: night }
    DarkModeToggle { id: dark }
    AntiFlashbangToggle { id: flash }

    component LevelRow: RowLayout {
        id: level
        property string glyph: ""
        property string label: ""
        property string figure: ""
        property real value: 0
        property bool ready: true
        signal moved(real value)
        Layout.fillWidth: true
        Layout.leftMargin: 10 * root.d
        Layout.rightMargin: 10 * root.d
        implicitHeight: Math.round(44 * root.d)
        spacing: 10 * root.d
        opacity: level.ready ? 1 : 0.45
        MaterialSymbol {
            Layout.preferredWidth: Math.round(28 * root.d)
            horizontalAlignment: Text.AlignHCenter
            text: level.glyph
            iconSize: Math.round(18 * root.d)
            color: IrisStyle.subtext
        }
        IrisText {
            Layout.preferredWidth: Math.round(78 * root.d)
            text: level.label
            font.pixelSize: IrisStyle.typeLabel
            elide: Text.ElideRight
        }
        IrisSlider {
            Layout.fillWidth: true
            enabled: level.ready
            value: level.value
            onMoved: next => level.moved(next)
        }
        IrisText {
            Layout.minimumWidth: Math.round(44 * root.d)
            horizontalAlignment: Text.AlignRight
            text: level.figure
            role: IrisText.Meta
            font.features: ({ "tnum": 1 })
        }
    }

    LevelRow {
        glyph: "light_mode"
        label: Translation.tr("Brightness")
        ready: Boolean(root.monitor?.ready) && Number.isFinite(root.brightness)
        value: ready ? root.brightness : 0
        figure: ready ? Math.round(root.brightness * 100) + "%" : ""
        onMoved: next => root.monitor?.setBrightness(next)
    }
    IrisControlRow {
        glyph: "nightlight"
        label: Translation.tr("Night Light")
        detail: Nightlight.scheduled ? Translation.tr("Sunset to sunrise") : Nightlight.clocked ? Translation.tr("On your hours") : Translation.tr("Until you turn it off")
        on: night.toggled
        tint: IrisStyle.identity.orange
        onToggled: night.mainAction()
    }
    LevelRow {
        glyph: "thermostat"
        label: Translation.tr("Warmth")
        value: (6500 - root.warmth) / 4000
        figure: root.warmth + " K"
        onMoved: next => Nightlight.setTemperature(Math.round((6500 - next * 4000) / 100) * 100)
    }
    IrisControlRow {
        glyph: "schedule"
        label: Translation.tr("On a schedule")
        detail: Translation.tr("Sunset to sunrise, on its own")
        on: Nightlight.scheduled
        onToggled: Nightlight.setScheduled(!Nightlight.scheduled)
    }
    IrisControlRow {
        glyph: "contrast"
        label: Translation.tr("Dark mode")
        detail: dark.toggled ? Translation.tr("Dark across the shell") : Translation.tr("Light across the shell")
        on: dark.toggled
        tint: IrisStyle.identity.indigo
        onToggled: dark.mainAction()
    }
    IrisControlRow {
        glyph: "flare"
        label: Translation.tr("Soften bright flashes")
        detail: Translation.tr("Dims a window that suddenly turns white")
        on: flash.toggled
        available: flash.available
        tint: IrisStyle.identity.yellow
        onToggled: flash.mainAction()
    }
}
