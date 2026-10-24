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
    readonly property var motion: root.cfg.motionOf(root.mode)

    function amount() {
        return root.motion && root.motion.amount ? root.motion.amount : "normal";
    }

    function pct(value) {
        return Math.round(Number(value) * 100) + "%";
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("CAMERA")
        kana: "視点"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Follow pointer")
            desc: I18n.tr("Move the camera with the cursor")
            controlWidth: Tokens.s7 + Tokens.s2
            Sw {
                anchors.right: parent.right
                on: root.cfg.followMouse(root.mode)
                onToggled: value => root.cfg.setMotion(root.mode, "mouse", value)
            }
        }

        SettingRow {
            enabled: root.cfg.followMouse(root.mode)
            width: parent.width
            divider: true
            label: I18n.tr("Sensitivity")
            desc: I18n.tr("How readily the camera follows small movements")
                + " · " + root.pct(root.cfg.sensitivity(root.mode))
            value: root.pct(root.cfg.sensitivity(root.mode))
            block: true
            Slid {
                width: parent.width
                from: 0
                to: 2
                value: root.cfg.sensitivity(root.mode)
                onModified: value => root.cfg.setMotion(root.mode, "sensitivity", value)
            }
        }

        SettingRow {
            enabled: root.cfg.followMouse(root.mode)
            width: parent.width
            divider: true
            label: I18n.tr("Range")
            desc: I18n.tr("The furthest the camera can travel")
                + " · " + root.pct(root.cfg.range(root.mode))
            value: root.pct(root.cfg.range(root.mode))
            block: true
            Slid {
                width: parent.width
                from: 0
                to: 2
                value: root.cfg.range(root.mode)
                onModified: value => root.cfg.setMotion(root.mode, "range", value)
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Strength")
            desc: I18n.tr("How strongly the depth map shapes the scene")
            block: true
            Seg {
                width: parent.width
                options: ["subtle", "normal", "strong"]
                labels: ({
                    subtle: I18n.tr("Subtle"),
                    normal: I18n.tr("Normal"),
                    strong: I18n.tr("Strong")
                })
                current: root.amount()
                onChose: value => root.cfg.setMotion(root.mode, "amount", value)
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Widget shadow direction")
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
            width: parent.width
            divider: true
            label: I18n.tr("Reset camera")
            desc: I18n.tr("Restore camera motion and widget lighting defaults")
            controlWidth: resetButton.implicitWidth
            Btn {
                id: resetButton
                text: I18n.tr("Reset")
                compact: true
                onAct: {
                    root.cfg.resetMotion(root.mode);
                    root.cfg.resetLook(root.mode);
                }
            }
        }
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("WIDGET DISTANCE")
        kana: "奥"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Set distance per widget")
            desc: I18n.tr("Each widget's distance is set from that widget's own page.")
        }
    }
}
