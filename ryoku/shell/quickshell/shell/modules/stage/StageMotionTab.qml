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

    function value(key, fallback) {
        return root.motion && root.motion[key] !== undefined ? root.motion[key] : fallback;
    }

    function pct(number) {
        return Math.round(Number(number) * 100) + "%";
    }

    function preset() {
        const amount = root.value("amount", "normal");
        const idle = root.value("idle", "none");
        const speed = Number(root.value("speed", 1));
        const music = root.value("music", false) === true;
        if (amount === "subtle" && idle === "float" && Math.abs(speed - 0.6) < 0.001 && !music)
            return "soft";
        if (amount === "normal" && idle === "sway" && Math.abs(speed - 0.5) < 0.001 && !music)
            return "cinematic";
        if (amount === "strong" && idle === "none" && Math.abs(speed - 1) < 0.001 && music)
            return "beat";
        return "";
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("PRESET")
        kana: "型"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Motion character")
            desc: I18n.tr("A preset stays selected only while all of its values still match")
            block: true
            Seg {
                width: parent.width
                options: ["soft", "cinematic", "beat"]
                labels: ({
                    soft: I18n.tr("Soft"),
                    cinematic: I18n.tr("Cinematic"),
                    beat: I18n.tr("Beat")
                })
                current: root.preset()
                onChose: value => root.cfg.applyPreset(value)
            }
        }
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("MOTION")
        kana: "動"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Amount")
            desc: I18n.tr("How far the whole composition travels")
            block: true
            Seg {
                width: parent.width
                options: ["subtle", "normal", "strong"]
                labels: ({
                    subtle: I18n.tr("Subtle"),
                    normal: I18n.tr("Normal"),
                    strong: I18n.tr("Strong")
                })
                current: root.value("amount", "normal")
                onChose: value => root.cfg.setMotion(root.mode, "amount", value)
            }
        }

        SettingRow {
            width: parent.width
            divider: true
            label: I18n.tr("Idle style")
            desc: I18n.tr("Movement while the pointer rests")
            block: true
            Seg {
                width: parent.width
                options: ["none", "float", "breathe", "sway"]
                labels: ({
                    none: I18n.tr("Still"),
                    float: I18n.tr("Float"),
                    breathe: I18n.tr("Breathe"),
                    sway: I18n.tr("Sway")
                })
                current: root.value("idle", "none")
                onChose: value => root.cfg.setMotion(root.mode, "idle", value)
            }
        }

        SettingRow {
            enabled: root.value("idle", "none") !== "none"
            width: parent.width
            divider: true
            label: I18n.tr("Idle speed")
            desc: I18n.tr("How quickly the idle movement loops")
                + " · " + Number(root.value("speed", 1)).toFixed(2) + "×"
            value: Number(root.value("speed", 1)).toFixed(2) + "×"
            block: true
            Slid {
                width: parent.width
                from: 0.25
                to: 2
                value: Number(root.value("speed", 1))
                onModified: value => root.cfg.setMotion(root.mode, "speed", value)
            }
        }
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("MUSIC")
        kana: "音"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("React to music")
            desc: I18n.tr("Near layers pulse with the beat")
            controlWidth: Tokens.s7 + Tokens.s2
            Sw {
                anchors.right: parent.right
                on: root.value("music", false) === true
                onToggled: value => root.cfg.setMotion(root.mode, "music", value)
            }
        }

        SettingRow {
            enabled: root.value("music", false) === true
            width: parent.width
            divider: true
            label: I18n.tr("Music intensity")
            desc: I18n.tr("How strongly the scene answers the beat")
                + " · " + root.pct(root.value("musicLevel", 0.6))
            value: root.pct(root.value("musicLevel", 0.6))
            block: true
            Slid {
                width: parent.width
                from: 0
                to: 1
                value: Number(root.value("musicLevel", 0.6))
                onModified: value => root.cfg.setMotion(root.mode, "musicLevel", value)
            }
        }
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("POINTER")
        kana: "指"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Follow pointer")
            desc: I18n.tr("Layers drift with the cursor")
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
            desc: I18n.tr("How readily the scene follows small movements")
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
            desc: I18n.tr("The furthest the cut-outs can travel")
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
            enabled: root.cfg.followMouse(root.mode)
            width: parent.width
            divider: true
            label: I18n.tr("Backdrop drift")
            desc: I18n.tr("Let the wallpaper move against the cut-outs")
                + " · " + root.pct(root.value("backdrop", 0.5))
            value: root.pct(root.value("backdrop", 0.5))
            block: true
            Slid {
                width: parent.width
                from: 0
                to: 1
                value: Number(root.value("backdrop", 0.5))
                onModified: value => root.cfg.setMotion(root.mode, "backdrop", value)
            }
        }
    }

    SettingCard {
        width: parent.width
        title: I18n.tr("RESET")
        kana: "戻"
        collapsible: false

        SettingRow {
            width: parent.width
            label: I18n.tr("Reset motion")
            desc: I18n.tr("Restore every Parallax motion setting")
            controlWidth: resetButton.implicitWidth
            Btn {
                id: resetButton
                text: I18n.tr("Reset")
                compact: true
                onAct: root.cfg.resetMotion(root.mode)
            }
        }
    }
}
