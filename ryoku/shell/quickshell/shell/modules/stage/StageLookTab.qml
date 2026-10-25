pragma ComponentBehavior: Bound

import QtQuick
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons" as StageCfg

Column {
    id: root

    required property string mode

    width: parent ? parent.width : 0
    spacing: Tokens.s4

    readonly property var cfg: StageCfg.Config

    function pct(value) {
        return Math.round(Number(value) * 100) + "%";
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("LOOK")
        kana: "質感"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Edge softness")
            desc: I18n.tr("Feather the boundary between a cut-out and its backdrop")
                + " · " + root.pct(root.cfg.edge(root.mode))
            value: root.pct(root.cfg.edge(root.mode))
            block: true
            Slid {
                width: parent.width
                from: 0
                to: 1
                value: root.cfg.edge(root.mode)
                onModified: value => root.cfg.setEdge(root.mode, value)
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Shadow strength")
            desc: I18n.tr("Separate near layers from the wallpaper")
                + " · " + root.pct(root.cfg.shadow(root.mode))
            value: root.pct(root.cfg.shadow(root.mode))
            block: true
            Slid {
                width: parent.width
                from: 0
                to: 1
                value: root.cfg.shadow(root.mode)
                onModified: value => root.cfg.setShadow(root.mode, value)
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Shadow direction")
            desc: I18n.tr("Drag around the dial to place the light")
                + " · " + Math.round(root.cfg.shadowAngle(root.mode)) + "°"
            value: Math.round(root.cfg.shadowAngle(root.mode)) + "°"
            block: true
            StageAngleDial {
                anchors.horizontalCenter: parent.horizontalCenter
                dim: Math.min(parent.width, Tokens.s7 * 2)
                implicitHeight: dim
                angle: root.cfg.shadowAngle(root.mode)
                onChanged: degrees => root.cfg.setShadowAngle(root.mode, degrees)
            }
        }

        SettingRow {
            visible: root.mode === "parallax"
            width: parent.width
            divider: true
            label: I18n.tr("3D backdrop")
            desc: I18n.tr("Use the Spatial depth map under the cut-outs when this wallpaper has one")
            controlWidth: Tokens.s7 + Tokens.s2
            Sw {
                anchors.right: parent.right
                on: root.cfg.depthBackdrop
                onToggled: value => root.cfg.setDepthBackdrop(value)
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Reset look")
            desc: I18n.tr("Restore edge, shadow and light direction defaults")
            controlWidth: resetButton.implicitWidth
            Btn {
                id: resetButton
                text: I18n.tr("Reset")
                compact: true
                onAct: root.cfg.resetLook(root.mode)
            }
        }
    }
}
