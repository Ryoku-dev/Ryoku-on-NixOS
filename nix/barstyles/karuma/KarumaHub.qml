pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "KarumaSchema.js" as Schema

/*
 * Karuma's configuration hub.
 *
 * Built the way Ryoku Settings is built: the same Ryoku.Ui parts (SettingCard,
 * SettingRow, Seg, Slid, Step, Sw, Btn), the same Tokens (so it follows Matugen
 * and the interface font exactly as the Hub does), and the same chrome: a rail
 * with a framed masthead and "// section" items, and pages that open with the
 * eyebrow / title / lede block. Sections: Appearance (the strip's look, bar size,
 * workspace style and motion), Geometry, Profiles, Modules, Plugins, Typography,
 * Progress, Behaviour, Clock & Date, Quick settings and Spacing.
 *
 * It owns no state of its own. Every control writes through `pal.config`
 * (KarumaConfig), the object the bar renders from, so a change repaints the
 * running bar at once and is saved to style.json a moment later.
 */
FloatingWindow {
    id: win

    required property var pal
    readonly property var cfg: pal.config
    readonly property var conf: pal.config.conf
    // What is playing, for the Indicator page's note (the bar's own media state, or null).
    property var media: null
    // Native Ryoku plugin catalogue/discovery, owned by Scene.qml.
    property var pluginHost: null
    // Hover fades and page changes in here follow the Animations switch too.
    readonly property bool animate: pal.animate
    // For the live previews on the Clock & Date page.
    property date now: new Date()
    property string profileName: ""
    Timer { interval: 1000; repeat: true; running: win.section === "clock"; onTriggered: win.now = new Date() }
    KarumaProfiles { id: profileStore; config: win.cfg }

    signal closeRequested()

    function pluginEntryForRef(ref) {
        const id = String(ref || "")
        if (id.indexOf("ryoku:") !== 0 || !win.pluginHost) return null
        return win.pluginHost.entryFor(id.slice(6))
    }
    function refLabel(ref) {
        const def = Schema.moduleById(String(ref))
        if (def) return I18n.tr(def.label)
        const entry = pluginEntryForRef(ref)
        const manifest = entry ? entry.manifest : null
        return manifest && manifest.name ? String(manifest.name) : String(ref).replace(/^ryoku:/, "")
    }
    function refDesc(ref) {
        const def = Schema.moduleById(String(ref))
        if (def) return I18n.tr(def.desc)
        const entry = pluginEntryForRef(ref)
        const manifest = entry ? entry.manifest : null
        return manifest && manifest.description ? String(manifest.description) : I18n.tr("Ryoku plugin glyph")
    }
    function refKana(ref) {
        const def = Schema.moduleById(String(ref))
        return def ? def.kana : "拡"
    }

    title: "Karuma"
    visible: true
    color: Tokens.paper

    // A fixed size makes tiling compositors float the window, so it opens as a
    // sheet in the middle of the screen like Ryoku Settings does.
    readonly property int fitW: (win.screen && win.screen.width > 0) ? Math.min(1040, win.screen.width - 40) : 1040
    readonly property int fitH: (win.screen && win.screen.height > 0) ? Math.min(720, win.screen.height - 80) : 720
    implicitWidth: fitW
    implicitHeight: fitH
    minimumSize: Qt.size(fitW, fitH)
    maximumSize: Qt.size(fitW, fitH)

    property string section: "appearance"
    readonly property var sections: [
        { key: "appearance", name: "Appearance", kana: "外観", eyebrow: "KARUMA / SURFACE", lede: "Paper, borders, curvature, scale and motion. Karuma keeps inner controls concentric with the surface instead of mixing unrelated corner radii." },
        { key: "geometry", name: "Geometry", kana: "配置", eyebrow: "KARUMA / GEOMETRY", lede: "Put Karuma on any screen edge, choose its length and alignment, and turn the side edges into a native vertical rail." },
        { key: "profiles", name: "Profiles", kana: "型", eyebrow: "KARUMA / PROFILES", lede: "Save the complete live Karuma document as a named profile, then switch designs without losing the one you built before it." },
        { key: "modules", name: "Modules", kana: "部品", eyebrow: "KARUMA / MODULES", lede: "Every built-in and Ryoku plugin is a placeable module. On a rail the same lanes become top, middle and bottom." },
        { key: "plugins", name: "Plugins", kana: "拡張", eyebrow: "KARUMA / PLUGINS", lede: "Native Ryoku top-bar plugins are first-class Karuma modules. Enable, place and configure them without leaving Karuma." },
        { key: "typography", name: "Typography", kana: "書体", eyebrow: "KARUMA / TYPE", lede: "Choose the display, interface, mono and Japanese faces independently, then scale text and iconography without changing bar geometry." },
        { key: "indicator", name: "Progress", kana: "進捗", eyebrow: "KARUMA / PROGRESS", lede: "Day or music progress can live on a module, one lane, one island, or the whole strip. Islands never bridge transparent gaps unless you explicitly ask them to." },
        { key: "behavior", name: "Behaviour", kana: "動作", eyebrow: "KARUMA / BEHAVIOUR", lede: "Choose how Karuma treats fullscreen windows and whether it reserves compositor space or floats over application geometry." },
        { key: "clock", name: "Clock & Date", kana: "時刻", eyebrow: "KARUMA / CLOCK", lede: "What Karuma’s clock module shows wherever you place it: the time, the date, and how each is written." },
        { key: "quick", name: "Quick settings", kana: "設定", eyebrow: "KARUMA / QUICK", lede: "Choose which controls the quick settings menu offers. Open the menu with the movable 設 module on the bar." },
        { key: "spacing", name: "Spacing", kana: "間隔", eyebrow: "KARUMA / SPACE", lede: "Screen gaps, module rhythm, island padding and the separation between independent surfaces." }
    ]
    readonly property var current: {
        for (let i = 0; i < win.sections.length; ++i)
            if (win.sections[i].key === win.section) return win.sections[i];
        return win.sections[0];
    }

    onClosed: { win.cfg.flushNow(); win.closeRequested(); }

    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: { win.cfg.flushNow(); win.closeRequested(); }

        // ── rail ────────────────────────────────────────────────────────────
        Item {
            id: rail
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: Tokens.railW
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Tokens.line }

            Column {
                id: railHead
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: Tokens.s5
                spacing: Tokens.s4

                // The masthead plate: framed, with the bar's own seal.
                Rectangle {
                    width: parent.width
                    height: 64
                    color: "transparent"
                    radius: Tokens.radius
                    border.width: Tokens.border
                    border.color: Tokens.line
                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.s4 }
                        spacing: Tokens.s3
                        Text { text: "業"; color: Tokens.ink; font.family: Tokens.jp; font.pixelSize: 22; anchors.verticalCenter: parent.verticalCenter }
                        Column {
                            spacing: 1
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: I18n.tr("KARUMA"); color: Tokens.ink; font.family: Tokens.ui
                                font.pixelSize: 14; font.weight: Font.Medium; font.letterSpacing: 2.4
                            }
                            Text {
                                text: I18n.tr("BAR SETTINGS"); color: Tokens.inkMuted
                                font.family: Tokens.mono; font.pixelSize: 10; font.letterSpacing: 1.4
                            }
                        }
                    }
                }
            }

            Column {
                anchors { left: parent.left; right: parent.right; top: railHead.bottom; topMargin: Tokens.s5 }
                anchors.leftMargin: Tokens.s5
                anchors.rightMargin: Tokens.s5

                Repeater {
                    model: win.sections
                    Item {
                        id: navItem
                        required property var modelData
                        readonly property bool sel: win.section === modelData.key
                        width: parent.width
                        height: 36

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 1; anchors.bottomMargin: 1
                            radius: Tokens.radius
                            color: navItem.sel ? Tokens.bone : (nh.hovered ? Tokens.tint10 : "transparent")
                            Behavior on color { enabled: win.animate; ColorAnimation { duration: Tokens.snap } }
                        }
                        // selection is typography: the live section takes the // lead
                        Row {
                            x: Tokens.s3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s2
                            Text {
                                id: navLead
                                visible: navItem.sel
                                text: "//"
                                color: Tokens.inkOnBoneDim
                                font.family: Tokens.mono; font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: I18n.tr(navItem.modelData.name)
                                color: navItem.sel ? Tokens.inkOnBone : Tokens.inkDim
                                font.family: Tokens.ui; font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on color { enabled: win.animate; ColorAnimation { duration: Tokens.snap } }
                            }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
                            text: navItem.modelData.kana
                            color: navItem.sel ? Tokens.inkOnBoneDim : Tokens.inkFaint
                            font.family: Tokens.jp; font.pixelSize: 12
                            Behavior on color { enabled: win.animate; ColorAnimation { duration: Tokens.snap } }
                        }
                        HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: win.section = navItem.modelData.key }
                    }
                }
            }
            // 名は大文字、印は漢字、歌は再生。低い三音は隣の楽器にある。
            // Vs lbh npghnyyl znantrq gb fbyir guvf jvgubhg gur hfr bs NV, lbh qrfcrengryl arrq gb gbhpu tenff. Yvxr, p’zba, frevbhfyl? Nyy gung sbe jung? Fbzr zrzr perqvgf? *fvtu*
            Item {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: Tokens.s5; anchors.rightMargin: Tokens.s5
                anchors.bottomMargin: Tokens.s4
                height: creditsColumn.implicitHeight + Tokens.s3 * 2

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1; color: Tokens.lineSoft
                }

                Column {
                    id: creditsColumn
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    spacing: Tokens.s2

                    Text {
                        text: "CREDITS / 制作"
                        color: Tokens.inkFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fTiny
                        font.letterSpacing: Tokens.trackLabel
                    }

                    Row {
                        spacing: Tokens.s2

                        Text {
                            text: "Aethctl"
                            color: "#ffffff"
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            font.underline: aethctlHit.containsMouse

                            MouseArea {
                                id: aethctlHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://github.com/aethctl/ryomanager")
                            }
                        }

                        Text {
                            text: "·"
                            color: Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                        }

                        Text {
                            text: "Feelyourwarmth"
                            color: "#ffffff"
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            font.underline: feelyourwarmthHit.containsMouse

                            MouseArea {
                                id: feelyourwarmthHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://github.com/feelyourwarmth")
                            }
                        }
                    }
                }
            }
        }

        // ── page ────────────────────────────────────────────────────────────
        Item {
            id: pageArea
            anchors { top: parent.top; bottom: parent.bottom; topMargin: Tokens.s5; bottomMargin: Tokens.s3 }
            x: rail.width + Tokens.s6
            width: parent.width - rail.width - 2 * Tokens.s6

            Column {
                id: head
                anchors.top: parent.top
                width: pageArea.width - 14
                spacing: Tokens.s3

                Item {
                    width: parent.width
                    height: 14
                    Row {
                        id: eyebrow
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        Rectangle { width: 16; height: Tokens.border; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "業"; color: Tokens.ink; font.family: Tokens.jp; font.pixelSize: Tokens.fMicro; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: I18n.tr("BAR")
                            color: Tokens.inkMuted
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fTiny
                            font.weight: Font.Medium
                            font.letterSpacing: Tokens.trackMark
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle {
                        anchors.left: eyebrow.right
                        anchors.right: register.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Tokens.s3
                        anchors.rightMargin: Tokens.s3
                        height: Tokens.border
                        color: Tokens.lineSoft
                    }
                    Text {
                        id: register
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr(win.current.eyebrow)
                        color: Tokens.inkFaint
                        font.family: Tokens.mono
                        font.pixelSize: Tokens.fTiny
                        font.letterSpacing: Tokens.trackLabel
                    }
                }
                Text {
                    text: I18n.tr(win.current.name)
                    color: Tokens.ink
                    font.family: Tokens.display
                    font.pixelSize: Tokens.fTitle
                }
                Text {
                    width: Math.min(parent.width, 720)
                    text: I18n.tr(win.current.lede)
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                    wrapMode: Text.WordWrap
                }
            }

            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom }
                anchors.topMargin: Tokens.s5
                contentWidth: width
                contentHeight: Math.max(height, (pageLoader.item ? pageLoader.item.height : 0) + Tokens.s5)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                QQC.ScrollBar.vertical: ScrollRail { policy: QQC.ScrollBar.AsNeeded }
                WheelScroll { }

                Loader {
                    id: pageLoader
                    width: flick.width - 14
                    sourceComponent: win.section === "spacing" ? spacingPage
                        : win.section === "geometry" ? geometryPage
                        : win.section === "profiles" ? profilesPage
                        : win.section === "modules" ? modulesPage
                        : win.section === "plugins" ? pluginsPage
                        : win.section === "typography" ? typographyPage
                        : win.section === "clock" ? clockPage
                        : win.section === "indicator" ? indicatorPage
                        : win.section === "behavior" ? behaviorPage
                        : win.section === "quick" ? quickPage : appearancePage
                    onLoaded: { flick.contentY = 0; if (win.animate) pageFade.restart(); }
                    NumberAnimation { id: pageFade; target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                }
            }
        }
    }

    // ── reset row shared by the pages ────────────────────────────────────────
    component ResetRow: SettingRow {
        id: resetRow
        property string which: "all"
        property string what: ""
        anchors.left: parent.left
        anchors.right: parent.right
        label: I18n.tr("Restore defaults")
        desc: resetRow.what
        source: "style.json"
        controlWidth: 100
        Btn {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("RESET")
            onAct: win.cfg.reset(resetRow.which)
        }
    }

    // One manifest-declared setting for a native Ryoku bar plugin. This is the
    // same public setting vocabulary QS Bar renders, but uses Karuma's sheet
    // chrome so a plugin never has to know which first-party bar is hosting it.
    component PluginSetting: Column {
        id: ps
        required property var entry
        required property var setting
        readonly property string pid: String(entry && entry.id ? entry.id : "")
        readonly property string skey: String(setting && setting.key ? setting.key : "")
        readonly property string stype: String(setting && setting.type ? setting.type : "")
        readonly property var opts: optionValues(setting)
        readonly property var optLabels: optionLabelMap(setting)
        readonly property bool allStrings: optionsAllStrings(setting)
        width: parent ? parent.width : 0
        spacing: Tokens.s2

        function currentValue() {
            const settings = entry && entry.placement && entry.placement.settings
                ? entry.placement.settings : ({})
            if (settings && settings[skey] !== undefined) return settings[skey]
            return setting && setting.default !== undefined ? setting.default : undefined
        }
        function save(value) { if (win.pluginHost) win.pluginHost.saveSetting(pid, skey, value) }
        function optionValues(spec) {
            const src = spec && Array.isArray(spec.options) ? spec.options : []
            const out = []
            for (let i = 0; i < src.length; ++i)
                out.push(src[i] && typeof src[i] === "object" ? String(src[i].value) : String(src[i]))
            return out
        }
        function optionLabelMap(spec) {
            const src = spec && Array.isArray(spec.options) ? spec.options : []
            const out = ({})
            for (let i = 0; i < src.length; ++i)
                if (src[i] && typeof src[i] === "object") out[String(src[i].value)] = String(src[i].label)
            return out
        }
        function optionsAllStrings(spec) {
            const src = spec && Array.isArray(spec.options) ? spec.options : []
            for (let i = 0; i < src.length; ++i)
                if (src[i] && typeof src[i] === "object") return false
            return true
        }

        Text {
            text: I18n.tr(ps.setting && ps.setting.label ? String(ps.setting.label) : ps.skey)
            color: Tokens.inkMuted
            font.family: Tokens.mono
            font.pixelSize: Tokens.fTiny
            font.letterSpacing: Tokens.trackLabel
        }

        Component {
            id: pluginSeg
            Seg {
                options: ps.opts
                current: { const v = ps.currentValue(); return v === undefined ? "" : String(v) }
                onChose: value => ps.save(value)
            }
        }
        Component {
            id: pluginChips
            Chips {
                width: ps.width
                options: ps.opts
                labels: ps.optLabels
                current: { const v = ps.currentValue(); return v === undefined ? "" : String(v) }
                onChose: value => ps.save(value)
            }
        }
        Component {
            id: pluginSwitch
            Sw {
                on: ps.currentValue() === true
                onToggled: value => ps.save(value)
            }
        }
        Component {
            id: pluginMulti
            Multi {
                width: ps.width
                options: ps.opts
                chosen: { const v = ps.currentValue(); return Array.isArray(v) ? v : [] }
                onToggled: key => {
                    const cur = ps.currentValue()
                    const values = Array.isArray(cur) ? cur.slice() : []
                    const at = values.indexOf(key)
                    if (at >= 0) values.splice(at, 1); else values.push(key)
                    ps.save(values)
                }
            }
        }
        Component {
            id: pluginStep
            Row {
                spacing: Tokens.s3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(stepper.value)
                    color: Tokens.ink
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fBody
                }
                Step {
                    id: stepper
                    anchors.verticalCenter: parent.verticalCenter
                    from: ps.setting && ps.setting.min !== undefined ? Number(ps.setting.min) : 0
                    to: ps.setting && ps.setting.max !== undefined ? Number(ps.setting.max) : 100
                    value: { const n = Number(ps.currentValue()); return isNaN(n) ? from : n }
                    onModified: value => ps.save(value)
                }
            }
        }
        Component {
            id: pluginField
            Field {
                width: Math.min(ps.width, 320)
                tabular: true
                text: { const v = ps.currentValue(); return v === undefined ? "" : String(v) }
                onCommitted: value => ps.save(value)
            }
        }

        Loader {
            readonly property bool wide: ps.stype === "multi" || ps.stype === "text"
                || (ps.stype === "choice" && !(ps.allStrings && ps.opts.length <= 4))
            width: wide ? ps.width : (item ? item.implicitWidth : 0)
            sourceComponent: {
                switch (ps.stype) {
                case "toggle": return pluginSwitch
                case "choice": return ps.allStrings && ps.opts.length <= 4 ? pluginSeg : pluginChips
                case "multi": return pluginMulti
                case "int": return pluginStep
                case "text": return pluginField
                default: return null
                }
            }
        }
    }

    // ── helpers for the pages ────────────────────────────────────────────────
    // A date pattern as the strip prints it (capitals, two lines joined by a dot).
    function datePreview(fmt) {
        const p = Schema.splitDate(fmt);
        const top = Qt.formatDate(win.now, p.top).toUpperCase();
        return p.bottom.length ? top + " · " + Qt.formatDate(win.now, p.bottom).toUpperCase() : top;
    }

    // What the Indicator page says about the music source.
    function musicStatus() {
        const m = win.media;
        if (!m) return I18n.tr("No media player found. The line stays empty until something plays.");
        if (!m.hasLength) return m.title + " · " + I18n.tr("this player does not report a track length, so the line stays empty.");
        return (m.playing ? I18n.tr("Following") : I18n.tr("Paused on")) + " " + m.title + " · " + Math.round(m.progress * 100) + "%";
    }

    // ── appearance ───────────────────────────────────────────────────────────
    Component {
        id: appearancePage
        Column {
            id: ap
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                id: lookCard
                width: parent.width
                title: I18n.tr("STRIP")
                kana: "帯"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    label: I18n.tr("Thickness")
                    desc: I18n.tr("Logical height of Top/Bottom Karuma. Side rails use their own width control under Geometry.")
                    source: "style.json"; unit: "px"; value: String(win.conf.height)
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 28; to: 80; value: win.conf.height
                        onModified: value => win.cfg.set("height", Math.round(value))
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Bar size")
                    desc: I18n.tr("Scales the whole strip together: its height, icons, text and spacing.")
                    source: "style.json"
                    unit: "%"
                    value: String(Math.round(win.conf.scale * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: Schema.SCALE_MIN; to: Schema.SCALE_MAX; value: win.conf.scale
                        onModified: value => win.cfg.set("scale", Math.round(value * 20) / 20)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Background opacity")
                    desc: I18n.tr("How solid the strip's paper is. The ink on it stays fully drawn.")
                    source: "style.json"
                    unit: "%"
                    value: String(Math.round(win.conf.opacity * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 0.2; to: 1; value: win.conf.opacity
                        onModified: value => win.cfg.set("opacity", Math.round(value * 100) / 100)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; block: true
                    label: I18n.tr("Layout")
                    desc: win.conf.layout === "islands"
                        ? I18n.tr("Three separate left, centre and right paper islands.")
                        : I18n.tr("One continuous paper strip across the bar.")
                    source: "style.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: [I18n.tr("Strip"), I18n.tr("Islands")]
                        current: win.conf.layout === "strip" ? I18n.tr("Strip") : I18n.tr("Islands")
                        onChose: label => win.cfg.set("layout", label === I18n.tr("Strip") ? "strip" : "islands")
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; controlWidth: 54
                    label: I18n.tr("Floating")
                    desc: win.conf.layout === "islands"
                        ? I18n.tr("Add outer space around the three islands.")
                        : I18n.tr("Lift the strip off the screen edges. Off is a full-width bar.")
                    source: "style.json"
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: win.conf.floating
                        onToggled: value => win.cfg.set("floating", value)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; block: true
                    label: I18n.tr("Shape")
                    desc: win.conf.layout === "islands"
                        ? I18n.tr("The corners of each island.")
                        : (win.conf.floating
                            ? I18n.tr("The ends of the floating strip.")
                            : I18n.tr("A full-width strip is always square. Turn on Floating to choose."))
                    source: "style.json"
                    enabled: win.conf.layout === "islands" || win.conf.floating
                    opacity: enabled ? 1 : 0.5
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: [I18n.tr("Square"), I18n.tr("Rounded"), I18n.tr("Pill")]
                        current: win.conf.shape === "square" ? I18n.tr("Square")
                            : win.conf.shape === "pill" ? I18n.tr("Pill") : I18n.tr("Rounded")
                        onChose: label => win.cfg.set("shape",
                            label === I18n.tr("Square") ? "square" : label === I18n.tr("Pill") ? "pill" : "rounded")
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Outer radius")
                    desc: I18n.tr("Rounded surfaces use this radius. Pill still follows half the surface thickness.")
                    source: "style.json"; unit: "px"; value: String(win.conf.cornerRadius)
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 48; value: win.conf.cornerRadius
                        onModified: value => win.cfg.set("cornerRadius", Math.round(value))
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Inner curve")
                    desc: I18n.tr("Offsets the automatically concentric module radius. Zero is mathematically matched.")
                    source: "style.json"; unit: "px"; value: (win.conf.innerRadiusBias > 0 ? "+" : "") + String(win.conf.innerRadiusBias)
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: -12; to: 12; value: win.conf.innerRadiusBias
                        onModified: value => win.cfg.set("innerRadiusBias", Math.round(value))
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Border width")
                    desc: I18n.tr("Outline thickness for the strip, islands and treated modules.")
                    source: "style.json"; unit: "px"; value: String(win.conf.borderWidth)
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 4; value: win.conf.borderWidth
                        onModified: value => win.cfg.set("borderWidth", Math.round(value * 2) / 2)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Border opacity")
                    desc: I18n.tr("How strongly the paper edge is drawn.")
                    source: "style.json"; unit: "%"; value: String(Math.round(win.conf.borderOpacity * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(lookCard.width * 0.34)))
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 1; value: win.conf.borderOpacity
                        onModified: value => win.cfg.set("borderOpacity", Math.round(value * 100) / 100)
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("PROFILES")
                kana: "型"
                collapsible: false

                Item {
                    width: parent.width
                    height: presetFlow.height + Tokens.s4 * 2
                    Flow {
                        id: presetFlow
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.s4 }
                        spacing: Tokens.s2
                        Repeater {
                            model: Schema.PRESETS
                            delegate: Rectangle {
                                id: preset
                                required property var modelData
                                width: Math.floor((presetFlow.width - presetFlow.spacing * 3) / 4)
                                height: 66
                                radius: Tokens.radius
                                color: presetHover.hovered ? Tokens.tint10 : "transparent"
                                border.width: Tokens.border
                                border.color: presetHover.hovered ? Tokens.sun : Tokens.line
                                Column {
                                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                    anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: I18n.tr(preset.modelData.label)
                                        color: Tokens.ink
                                        font.family: Tokens.ui; font.pixelSize: Tokens.fSmall; font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: I18n.tr(preset.modelData.desc)
                                        color: Tokens.inkFaint
                                        font.family: Tokens.ui; font.pixelSize: Tokens.fTiny
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }
                                }
                                HoverHandler { id: presetHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: win.cfg.applyPreset(preset.modelData.id) }
                            }
                        }
                    }
                }
            }

            SettingCard {
                id: wsCard
                width: parent.width
                title: I18n.tr("WORKSPACES")
                kana: "頁"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Workspace style")
                    desc: I18n.tr(Schema.WORKSPACE_STYLES.filter(function (w) { return w.id === win.conf.workspaceStyle; })[0].desc) + " " + I18n.tr("Applies to the running bar at once.")
                    source: "style.json"

                    Row {
                        id: wsStyles
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        readonly property real cellW: Math.floor((width - spacing * (Schema.WORKSPACE_STYLES.length - 1)) / Schema.WORKSPACE_STYLES.length)

                        Repeater {
                            model: Schema.WORKSPACE_STYLES
                            Rectangle {
                                id: styleCard
                                required property var modelData
                                readonly property bool sel: win.conf.workspaceStyle === modelData.id
                                width: wsStyles.cellW
                                height: 92
                                radius: Tokens.radius
                                color: styleCard.sel ? Tokens.bone : (sh.hovered ? Tokens.tint10 : "transparent")
                                border.width: Tokens.border
                                border.color: styleCard.sel ? Tokens.bone : Tokens.line
                                Behavior on color { enabled: win.animate; ColorAnimation { duration: Tokens.snap } }

                                // Three sample marks, the middle one live, drawn like the strip draws them.
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 16
                                    spacing: styleCard.modelData.id === "dashes" ? 3 : (styleCard.modelData.id === "dots" ? 5 : 8)
                                    Repeater {
                                        model: 3
                                        Item {
                                            id: mark
                                            required property int index
                                            readonly property bool live: index === 1
                                            readonly property string id: styleCard.modelData.id
                                            readonly property color fg: styleCard.sel ? Tokens.inkOnBone : Tokens.ink
                                            readonly property color faint: styleCard.sel ? Tokens.inkOnBoneDim : Tokens.inkFaint
                                            width: id === "dashes" ? (live ? 20 : 12) : (id === "dots" ? 10 : 18)
                                            height: 22
                                            Text {
                                                visible: mark.id === "kanji" || mark.id === "numbers" || mark.id === "roman"
                                                anchors.centerIn: parent
                                                text: Schema.workspaceText(mark.id, mark.index + 1, ["壱", "弐", "参"][mark.index])
                                                color: mark.live ? mark.fg : mark.faint
                                                font.family: mark.id === "kanji" ? Tokens.jp : (mark.id === "roman" ? Tokens.display : Tokens.ui)
                                                font.pixelSize: mark.id === "kanji" ? 15 : 14
                                                font.underline: false
                                            }
                                            Rectangle {
                                                visible: mark.id === "dashes"
                                                anchors.centerIn: parent
                                                width: parent.width; height: mark.live ? 3 : 2; radius: height / 2
                                                color: mark.live ? mark.fg : mark.faint
                                            }
                                            Rectangle {
                                                visible: mark.id === "dots"
                                                anchors.centerIn: parent
                                                width: mark.live ? 9 : 6; height: width; radius: width / 2
                                                color: mark.live ? mark.fg : "transparent"
                                                border.width: mark.live ? 0 : 1
                                                border.color: mark.faint
                                            }
                                        }
                                    }
                                }

                                Column {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 10 }
                                    anchors.leftMargin: Tokens.s2; anchors.rightMargin: Tokens.s2
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: I18n.tr(styleCard.modelData.label)
                                        color: styleCard.sel ? Tokens.inkOnBone : Tokens.ink
                                        font.family: Tokens.ui; font.pixelSize: 13; font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: styleCard.sel ? I18n.tr("IN USE") : (styleCard.modelData.id === "kanji" ? I18n.tr("DEFAULT") : " ")
                                        color: styleCard.sel ? Tokens.inkOnBoneDim : Tokens.inkFaint
                                        font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                                        font.letterSpacing: Tokens.trackLabel
                                    }
                                }

                                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: win.cfg.set("workspaceStyle", styleCard.modelData.id) }
                            }
                        }
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("MOTION")
                kana: "動"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    controlWidth: 54
                    label: I18n.tr("Animations")
                    desc: I18n.tr("Fades, slides and transitions on the strip, its pop-ups and menus, and this hub. Off makes every change immediate.")
                    source: "style.json"
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: win.conf.animations
                        onToggled: value => win.cfg.set("motion", value ? "paper" : "still")
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "appearance"; what: I18n.tr("Normal size, shipped opacity, islands layout, floating rounded shape, kanji workspaces, animations on.") }
            }
        }
    }

    // ── clock & date ─────────────────────────────────────────────────────────
    Component {
        id: clockPage
        Column {
            id: cp
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("TIME")
                kana: "時"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    controlWidth: 54
                    label: I18n.tr("Show time")
                    desc: I18n.tr("The clock itself. The date can stay on its own.")
                    source: "style.json"
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: win.conf.showClock
                        onToggled: value => win.cfg.set("showClock", value)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; block: true
                    label: I18n.tr("Time format")
                    desc: I18n.tr("Reads") + " " + Qt.formatTime(win.now, win.conf.hours === "24h" ? "HH:mm" : "h:mm AP")
                    source: "style.json"
                    enabled: win.conf.showClock
                    opacity: win.conf.showClock ? 1 : 0.5
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: [I18n.tr("12-hour"), I18n.tr("24-hour")]
                        current: win.conf.hours === "24h" ? I18n.tr("24-hour") : I18n.tr("12-hour")
                        onChose: label => win.cfg.set("hours", label === I18n.tr("24-hour") ? "24h" : "12h")
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DATE")
                kana: "暦"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    controlWidth: 54
                    label: I18n.tr("Show date")
                    desc: I18n.tr("Beside the time, or alone when the time is off. On a very crowded strip the date steps aside first.")
                    source: "style.json"
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: win.conf.showDate
                        onToggled: value => win.cfg.set("showDate", value)
                    }
                }

                // Presets, then a pattern of your own. Every change is on the strip at once.
                Item {
                    width: parent.width
                    height: dateCol.height + Tokens.s4 * 2
                    enabled: win.conf.showDate
                    opacity: win.conf.showDate ? 1 : 0.5

                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Tokens.lineSoft }

                    Column {
                        id: dateCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.s4 }
                        spacing: Tokens.s3

                        Text {
                            text: I18n.tr("FORMAT")
                            color: Tokens.inkMuted
                            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.letterSpacing: Tokens.trackLabel
                        }

                        Flow {
                            id: chips
                            width: parent.width
                            spacing: Tokens.s2

                            Repeater {
                                model: Schema.DATE_PRESETS
                                delegate: Rectangle {
                                    id: chip
                                    required property string modelData
                                    readonly property bool sel: win.conf.dateFormat === modelData
                                    width: Math.floor((chips.width - 2 * chips.spacing) / 3)
                                    height: 48
                                    radius: Tokens.radius
                                    color: chip.sel ? Tokens.bone : (chipHover.hovered ? Tokens.tint10 : "transparent")
                                    border.width: Tokens.border
                                    border.color: chip.sel ? Tokens.bone : Tokens.line
                                    Behavior on color { enabled: win.animate; ColorAnimation { duration: Tokens.snap } }

                                    Column {
                                        anchors.centerIn: parent
                                        width: parent.width - 2 * Tokens.s2
                                        spacing: 2
                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: win.datePreview(chip.modelData)
                                            color: chip.sel ? Tokens.inkOnBone : Tokens.ink
                                            font.family: Tokens.mono; font.pixelSize: Tokens.fSmall
                                        }
                                        Text {
                                            width: parent.width
                                            horizontalAlignment: Text.AlignHCenter
                                            elide: Text.ElideRight
                                            text: chip.modelData
                                            color: chip.sel ? Tokens.inkOnBoneDim : Tokens.inkFaint
                                            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
                                        }
                                    }
                                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: win.cfg.set("dateFormat", chip.modelData) }
                                }
                            }
                        }

                        Text {
                            text: I18n.tr("CUSTOM PATTERN")
                            color: Tokens.inkMuted
                            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.letterSpacing: Tokens.trackLabel
                        }

                        Rectangle {
                            id: field
                            width: parent.width
                            height: Tokens.ctlH + 6
                            radius: Tokens.radius
                            color: Tokens.paperLift
                            border.width: Tokens.border
                            border.color: input.activeFocus ? Tokens.ink : Tokens.line

                            TextInput {
                                id: input
                                anchors { left: parent.left; right: shown.left; verticalCenter: parent.verticalCenter }
                                anchors.leftMargin: Tokens.s3; anchors.rightMargin: Tokens.s3
                                color: Tokens.ink
                                font.family: Tokens.mono; font.pixelSize: Tokens.fBody
                                selectByMouse: true
                                clip: true
                                maximumLength: 32
                                selectionColor: Tokens.bone
                                selectedTextColor: Tokens.inkOnBone
                                Component.onCompleted: text = win.conf.dateFormat
                                onTextEdited: win.cfg.set("dateFormat", text)
                            }
                            Text {
                                anchors.left: input.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: input.text.length === 0
                                text: Schema.DEFAULT_DATE
                                color: Tokens.inkFaint
                                font.family: Tokens.mono; font.pixelSize: Tokens.fBody
                            }
                            Text {
                                id: shown
                                anchors { right: parent.right; rightMargin: Tokens.s3; verticalCenter: parent.verticalCenter }
                                text: win.datePreview(win.conf.dateFormat)
                                color: Tokens.inkDim
                                font.family: Tokens.mono; font.pixelSize: Tokens.fSmall
                            }
                            // While you are typing the field is yours; any other change (a preset, a reset) lands in it.
                            Connections {
                                target: win
                                function onConfChanged() { if (!input.activeFocus) input.text = win.conf.dateFormat; }
                            }
                        }

                        Text {
                            width: parent.width
                            text: I18n.tr("A Qt date pattern: d dd ddd dddd for the day, M MM MMM MMMM for the month, yy yyyy for the year. Put | between two parts to stack them on two lines, and wrap any literal letters in 'single quotes'. The strip prints the date in capitals. Clear the field to return to the default.")
                            color: Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "clock"; what: I18n.tr("Time and date shown, 12-hour clock, the default date pattern.") }
            }
        }
    }

    // ── progress ─────────────────────────────────────────────────────────────
    Component {
        id: indicatorPage
        Column {
            id: ip
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("SOURCE")
                kana: "源"
                collapsible: false
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Progress source")
                    desc: win.conf.indicator === "disabled" ? I18n.tr("Progress is disabled.")
                        : win.conf.indicator === "music" ? I18n.tr("Follow the current track position when the player reports a duration.")
                        : I18n.tr("Fill from midnight to midnight using the local time.")
                    source: "style.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: [I18n.tr("Off"), I18n.tr("Day"), I18n.tr("Music")]
                        current: win.conf.indicator === "disabled" ? I18n.tr("Off") : win.conf.indicator === "music" ? I18n.tr("Music") : I18n.tr("Day")
                        onChose: label => win.cfg.set("indicator", label === I18n.tr("Off") ? "disabled" : label === I18n.tr("Music") ? "music" : "daily")
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("PRESENTATION")
                kana: "線"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Style")
                    desc: I18n.tr("Choose how progress is drawn. Accent uses the live Ryoku primary colour.")
                    source: "style.json"
                    Chips {
                        anchors.left: parent.left; anchors.right: parent.right
                        options: ["none", "hairline", "track", "fill", "accent"]
                        labels: ({ none: I18n.tr("None"), hairline: I18n.tr("Hairline"), track: I18n.tr("Track"), fill: I18n.tr("Fill"), accent: I18n.tr("Accent") })
                        current: win.conf.progressStyle
                        onChose: value => win.cfg.set("progressStyle", value)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; block: true
                    label: I18n.tr("Placement")
                    desc: win.conf.layout === "islands" && win.conf.progressPlacement === "auto"
                        ? I18n.tr("Automatic keeps progress on the centre island. It never crosses the transparent channels.")
                        : I18n.tr("Attach progress to a module, lane/island, or deliberately span the whole Karuma surface.")
                    source: "style.json"
                    Chips {
                        anchors.left: parent.left; anchors.right: parent.right
                        options: ["auto", "module", "left", "center", "right", "whole"]
                        labels: ({ auto: I18n.tr("Automatic"), module: I18n.tr("Module"), left: I18n.tr("Left / Top"), center: I18n.tr("Centre / Middle"), right: I18n.tr("Right / Bottom"), whole: I18n.tr("Whole bar") })
                        current: win.conf.progressPlacement
                        onChose: value => win.cfg.set("progressPlacement", value)
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Thickness")
                    desc: I18n.tr("Track thickness in logical pixels.")
                    source: "style.json"; unit: "px"; value: String(win.conf.progressThickness)
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 1; to: 8; value: win.conf.progressThickness; onModified: value => win.cfg.set("progressThickness", Math.round(value)) }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Opacity")
                    desc: I18n.tr("Strength of the filled portion and playhead.")
                    source: "style.json"; unit: "%"; value: String(Math.round(win.conf.progressOpacity * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 0.1; to: 1; value: win.conf.progressOpacity; onModified: value => win.cfg.set("progressOpacity", Math.round(value * 100) / 100) }
                }
            }

            Text {
                visible: win.conf.indicator === "music"
                width: parent.width
                text: win.musicStatus()
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "indicator"; what: I18n.tr("Restore the default day-progress treatment.") }
            }
        }
    }

    // ── quick settings ───────────────────────────────────────────────────────
    Component {
        id: quickPage
        Column {
            id: qp
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("CONTROLS")
                kana: "操"

                Repeater {
                    model: Schema.QUICK
                    delegate: SettingRow {
                        required property var modelData
                        required property int index
                        anchors.left: parent.left; anchors.right: parent.right
                        divider: index > 0
                        controlWidth: 54
                        label: I18n.tr(modelData.label)
                        desc: I18n.tr(modelData.desc)
                        source: "style.json"
                        Sw {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            on: win.conf.quickHidden.indexOf(modelData.id) < 0
                            onToggled: value => win.cfg.setQuickHidden(modelData.id, !value)
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: I18n.tr("A control the machine has no hardware for (brightness on a desktop, Bluetooth with no adapter) is left out of the menu automatically. The 設 button is a module: hide or move it under Modules.")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "quick"; what: I18n.tr("Offer every control.") }
            }
        }
    }


    // ── behaviour ──────────────────────────────────────────────────────────
    Component {
        id: behaviorPage
        Column {
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("WINDOWS")
                kana: "動"
                collapsible: false

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Fullscreen")
                    desc: win.conf.fullscreenMode === "hide"
                        ? I18n.tr("Hide the visible Karuma surface while the active output is fullscreen. The reserve band stays stable when enabled below.")
                        : I18n.tr("Keep Karuma visible above fullscreen windows.")
                    source: "style.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        options: [I18n.tr("Hide"), I18n.tr("Keep visible")]
                        current: win.conf.fullscreenMode === "show" ? I18n.tr("Keep visible") : I18n.tr("Hide")
                        onChose: label => win.cfg.set("fullscreenMode", label === I18n.tr("Keep visible") ? "show" : "hide")
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; block: true
                    label: I18n.tr("Window space")
                    desc: win.conf.reserveSpace
                        ? I18n.tr("Reserve the Karuma band so tiled windows never sit underneath it.")
                        : I18n.tr("Overlay application geometry. Useful for fully floating or auto-managed desktop layouts.")
                    source: "style.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        options: [I18n.tr("Reserve"), I18n.tr("Overlay")]
                        current: win.conf.reserveSpace ? I18n.tr("Reserve") : I18n.tr("Overlay")
                        onChose: label => win.cfg.set("reserveSpace", label === I18n.tr("Reserve"))
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "behavior"; what: I18n.tr("Hide Karuma for fullscreen windows and reserve compositor space for its edge band.") }
            }
        }
    }

    // ── geometry ────────────────────────────────────────────────────────────
    Component {
        id: geometryPage
        Column {
            id: gp
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("EDGE")
                kana: "辺"
                collapsible: false

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Screen edge")
                    desc: (win.conf.edge === "left" || win.conf.edge === "right")
                        ? I18n.tr("Vertical Rail renderer. Text and plugins stay upright; Karuma does not rotate a horizontal bar.")
                        : I18n.tr("Horizontal renderer on the selected edge.")
                    source: "style.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: [I18n.tr("Top"), I18n.tr("Bottom"), I18n.tr("Left"), I18n.tr("Right")]
                        current: win.conf.edge === "bottom" ? I18n.tr("Bottom")
                            : win.conf.edge === "left" ? I18n.tr("Left")
                            : win.conf.edge === "right" ? I18n.tr("Right") : I18n.tr("Top")
                        onChose: label => win.cfg.set("edge",
                            label === I18n.tr("Bottom") ? "bottom" : label === I18n.tr("Left") ? "left"
                            : label === I18n.tr("Right") ? "right" : "top")
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true; block: true
                    label: I18n.tr("Alignment")
                    desc: I18n.tr("Where a shortened bar sits along its edge.")
                    source: "style.json"
                    Seg {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        options: [I18n.tr("Start"), I18n.tr("Centre"), I18n.tr("End")]
                        current: win.conf.align === "start" ? I18n.tr("Start") : win.conf.align === "end" ? I18n.tr("End") : I18n.tr("Centre")
                        onChose: label => win.cfg.set("align", label === I18n.tr("Start") ? "start" : label === I18n.tr("End") ? "end" : "center")
                    }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Length")
                    desc: I18n.tr("Percentage of the usable screen edge occupied by Karuma.")
                    source: "style.json"; unit: "%"; value: String(win.conf.length)
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 28; to: 100; value: win.conf.length; onModified: value => win.cfg.set("length", Math.round(value)) }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Lane spread")
                    desc: I18n.tr("0% packs the three lanes together using Island separation; 100% pushes them to the classic outer / centre / outer positions.")
                    source: "style.json"; unit: "%"; value: String(Math.round(win.conf.laneSpread * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 0; to: 1; value: win.conf.laneSpread; onModified: value => win.cfg.set("laneSpread", Math.round(value * 100) / 100) }
                }

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Rail width")
                    desc: I18n.tr("Thickness of the native Left/Right renderer. Stored even while Karuma is horizontal.")
                    source: "style.json"; unit: "px"; value: String(win.conf.railWidth)
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 44; to: 128; value: win.conf.railWidth; onModified: value => win.cfg.set("railWidth", Math.round(value)) }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "geometry"; what: I18n.tr("Return Karuma to the top edge at full length, centred alignment and classic lane spread.") }
            }
        }
    }


    // ── profiles ────────────────────────────────────────────────────────────
    Component {
        id: profilesPage
        Column {
            id: prp
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("SAVE CURRENT")
                kana: "保"
                collapsible: false
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    block: true
                    label: I18n.tr("Profile name")
                    desc: I18n.tr("Profiles store the entire Karuma style document: geometry, modules, fonts, progress and future-compatible keys.")
                    source: "profiles.json"
                    Row {
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.s2
                        Field {
                            width: Math.max(180, parent.width - saveBtn.width - parent.spacing)
                            text: win.profileName
                            onEdited: value => win.profileName = value
                            onCommitted: value => win.profileName = value
                        }
                        Btn {
                            id: saveBtn
                            text: I18n.tr("SAVE")
                            onAct: {
                                if (profileStore.save(win.profileName))
                                    win.profileName = ""
                            }
                        }
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("MY PROFILES")
                kana: "型"
                collapsible: false

                Item {
                    visible: profileStore.names.length === 0
                    width: parent.width
                    height: visible ? 58 : 0
                    Text {
                        anchors.centerIn: parent
                        text: I18n.tr("No saved profiles yet.")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                    }
                }

                Repeater {
                    model: profileStore.names
                    delegate: Item {
                        id: profileRow
                        required property string modelData
                        required property int index
                        width: parent ? parent.width : 0
                        height: 54
                        Rectangle { anchors.top: parent.top; width: parent.width; height: index > 0 ? 1 : 0; color: Tokens.lineSoft }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: Tokens.s4
                            anchors.verticalCenter: parent.verticalCenter
                            text: profileRow.modelData
                            color: Tokens.ink
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fBody
                            font.weight: Font.Medium
                        }
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: Tokens.s4
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.s2
                            Btn { text: I18n.tr("APPLY"); onAct: profileStore.apply(profileRow.modelData) }
                            Btn { text: I18n.tr("UPDATE"); onAct: profileStore.save(profileRow.modelData) }
                            Btn { text: I18n.tr("DELETE"); onAct: profileStore.remove(profileRow.modelData) }
                        }
                    }
                }
            }
        }
    }

    // ── typography ──────────────────────────────────────────────────────────
    Component {
        id: typographyPage
        Column {
            id: tp
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("SCALE")
                kana: "字"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    label: I18n.tr("Text scale")
                    desc: I18n.tr("Changes Karuma type without changing the surface or icon geometry.")
                    source: "style.json"; unit: "%"; value: String(Math.round(win.conf.textScale * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 0.65; to: 1.8; value: win.conf.textScale; onModified: value => win.cfg.set("textScale", Math.round(value * 100) / 100) }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    label: I18n.tr("Icon scale")
                    desc: I18n.tr("Scales seals, stamps and iconography independently of text.")
                    source: "style.json"; unit: "%"; value: String(Math.round(win.conf.iconScale * 100))
                    controlWidth: Math.min(240, Math.max(160, Math.round(parent.width * 0.34)))
                    Slid { anchors.fill: parent; from: 0.65; to: 1.8; value: win.conf.iconScale; onModified: value => win.cfg.set("iconScale", Math.round(value * 100) / 100) }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("FAMILIES")
                kana: "書"
                collapsible: false

                Repeater {
                    model: [
                        { key: "displayFont", label: "Display / serif", desc: "Clock, titles and media. Empty uses bundled Fraunces." },
                        { key: "textFont", label: "Interface", desc: "Values and labels. Empty uses bundled Space Grotesk." },
                        { key: "monoFont", label: "Monospace", desc: "Micro labels and tabular text. Empty follows Karuma's fallback chain." },
                        { key: "jpFont", label: "Japanese / seals", desc: "Kanji marks and seals. Empty uses bundled Yuji Boku." }
                    ]
                    delegate: SettingRow {
                        required property var modelData
                        required property int index
                        anchors.left: parent.left; anchors.right: parent.right
                        divider: index > 0
                        block: true
                        label: I18n.tr(modelData.label)
                        desc: I18n.tr(modelData.desc)
                        source: "style.json"
                        Field {
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(win.cfg.raw[modelData.key] || "")
                            onCommitted: value => win.cfg.set(modelData.key, value)
                        }
                    }
                }
            }
            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "typography"; what: I18n.tr("Return font families and independent text/icon scaling to Karuma defaults.") }
            }

        }
    }

    // ── spacing ──────────────────────────────────────────────────────────────
    Component {
        id: spacingPage
        Column {
            id: sp
            width: pageLoader.width
            spacing: Tokens.s4

            readonly property var sides: [
                { key: "top", label: "Top", desc: "Between the strip and the top edge of the screen." },
                { key: "bottom", label: "Bottom", desc: "Between the strip and the windows below it." },
                { key: "left", label: "Left", desc: "Between the strip and the left edge." },
                { key: "right", label: "Right", desc: "Between the strip and the right edge." }
            ]

            SettingCard {
                width: parent.width
                title: I18n.tr("GAPS")
                kana: "隙"

                Repeater {
                    model: sp.sides
                    delegate: SettingRow {
                        required property var modelData
                        required property int index
                        anchors.left: parent.left; anchors.right: parent.right
                        divider: index > 0
                        controlWidth: 58
                        label: I18n.tr(modelData.label)
                        desc: win.conf.floating ? I18n.tr(modelData.desc) : I18n.tr("Used while the bar floats.")
                        source: "style.json"; unit: "px"
                        value: String(win.conf.gap[modelData.key])
                        enabled: win.conf.floating
                        opacity: win.conf.floating ? 1 : 0.5
                        Step {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            from: 0; to: 64; value: win.conf.gap[modelData.key]
                            onModified: value => win.cfg.setGap(modelData.key, value)
                        }
                    }
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("RHYTHM")
                kana: "間"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    controlWidth: 58
                    label: I18n.tr("Module gap")
                    desc: I18n.tr("Space between neighbouring modules inside a lane.")
                    source: "style.json"; unit: "px"; value: String(win.conf.moduleGap)
                    Step {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 40; value: win.conf.moduleGap
                        onModified: value => win.cfg.set("moduleGap", value)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: 58
                    label: I18n.tr("Island padding")
                    desc: I18n.tr("Paper breathing room around each populated lane in Islands mode.")
                    source: "style.json"; unit: "px"; value: String(win.conf.islandPad)
                    Step {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 28; value: win.conf.islandPad
                        onModified: value => win.cfg.set("islandPad", value)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: 58
                    label: I18n.tr("Island separation")
                    desc: I18n.tr("Gap between lanes when Lane spread is packed. Increasing spread progressively opens the layout toward the screen edges.")
                    source: "style.json"; unit: "px"; value: String(win.conf.islandGap)
                    Step {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        from: 0; to: 48; value: win.conf.islandGap
                        onModified: value => win.cfg.set("islandGap", value)
                    }
                }

            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "spacing"; what: I18n.tr("Return all four gaps to their shipped values.") }
            }
        }
    }

    // ── modules ──────────────────────────────────────────────────────────────
    Component {
        id: modulesPage
        Column {
            id: mp
            width: pageLoader.width
            spacing: Tokens.s4

            function rowsFor(lane) {
                const base = (win.conf.lanes[lane] || []).slice()
                if (!win.pluginHost) return base
                const ids = win.pluginHost.pluginIds || []
                for (let i = 0; i < ids.length; ++i) {
                    const ref = "ryoku:" + ids[i]
                    let placed = false
                    for (let j = 0; j < Schema.LANES.length; ++j)
                        if ((win.conf.lanes[Schema.LANES[j]] || []).indexOf(ref) >= 0) placed = true
                    if (!placed && win.pluginHost.defaultLane(ids[i]) === lane) base.push(ref)
                }
                return base
            }
            function laneName(lane) {
                const vertical = win.conf.edge === "left" || win.conf.edge === "right"
                if (vertical) return lane === "left" ? I18n.tr("TOP") : lane === "center" ? I18n.tr("MIDDLE") : I18n.tr("BOTTOM")
                return lane === "left" ? I18n.tr("LEFT") : lane === "center" ? I18n.tr("CENTRE") : I18n.tr("RIGHT")
            }
            function previousLane(lane) {
                const i = Schema.LANES.indexOf(lane)
                return i > 0 ? Schema.LANES[i - 1] : ""
            }
            function nextLane(lane) {
                const i = Schema.LANES.indexOf(lane)
                return i >= 0 && i < Schema.LANES.length - 1 ? Schema.LANES[i + 1] : ""
            }
            function nextStyle(id) {
                const current = Schema.styleFor(win.conf, id)
                const at = Schema.MODULE_STYLES.indexOf(current)
                return Schema.MODULE_STYLES[(at + 1) % Schema.MODULE_STYLES.length]
            }

            Repeater {
                model: Schema.LANES
                delegate: SettingCard {
                    id: laneCard
                    required property string modelData
                    readonly property string lane: modelData
                    width: mp.width
                    title: mp.laneName(lane)
                    kana: lane === "left" ? "左" : lane === "center" ? "中" : "右"
                    collapsible: false

                    Repeater {
                        id: laneRows
                        model: mp.rowsFor(laneCard.lane)
                        delegate: Item {
                            id: slot
                            required property string modelData
                            required property int index
                            width: laneCard.width
                            height: 118
                            readonly property string ref: modelData
                            readonly property bool shown: win.conf.hidden.indexOf(ref) < 0
                            readonly property string treatment: Schema.styleFor(win.conf, ref)
                            readonly property var options: Schema.moduleOptions(win.conf, ref)

                            Rectangle { anchors.top: parent.top; width: parent.width; height: index > 0 ? 1 : 0; color: Tokens.lineSoft }

                            Text {
                                id: kana
                                anchors.left: parent.left
                                anchors.leftMargin: Tokens.s4
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -28
                                text: win.refKana(slot.ref)
                                color: slot.ref.indexOf("ryoku:") === 0 ? Tokens.sun : Tokens.ink
                                font.family: Tokens.jp
                                font.pixelSize: 18
                            }
                            Column {
                                anchors.left: kana.right
                                anchors.leftMargin: Tokens.s3
                                anchors.right: controls.left
                                anchors.rightMargin: Tokens.s2
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -28
                                spacing: 1
                                Text {
                                    width: parent.width
                                    text: win.refLabel(slot.ref)
                                    color: Tokens.ink
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fBody
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: win.refDesc(slot.ref) + " · " + slot.treatment.toUpperCase()
                                    color: Tokens.inkMuted
                                    font.family: Tokens.ui
                                    font.pixelSize: Tokens.fSmall
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                id: controls
                                anchors.right: parent.right
                                anchors.rightMargin: Tokens.s3
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -28
                                spacing: 2

                                Repeater {
                                    model: [
                                        { icon: "keyboard_double_arrow_left", kind: "lanePrev" },
                                        { icon: "keyboard_arrow_up", kind: "up" },
                                        { icon: "keyboard_arrow_down", kind: "down" },
                                        { icon: "keyboard_double_arrow_right", kind: "laneNext" },
                                        { icon: "palette", kind: "style" },
                                        { icon: slot.shown ? "visibility" : "visibility_off", kind: "visible" }
                                    ]
                                    delegate: Rectangle {
                                        id: ctl
                                        required property var modelData
                                        readonly property bool can: modelData.kind === "lanePrev" ? mp.previousLane(laneCard.lane).length > 0
                                            : modelData.kind === "laneNext" ? mp.nextLane(laneCard.lane).length > 0
                                            : modelData.kind === "up" ? slot.index > 0
                                            : modelData.kind === "down" ? slot.index < laneRows.count - 1 : true
                                        width: Tokens.ctlH; height: width
                                        radius: Tokens.radius
                                        color: ctlHover.hovered && can ? Tokens.tint10 : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: ctl.modelData.icon
                                            color: ctl.can ? Tokens.inkDim : Tokens.inkFaint
                                            opacity: ctl.can ? 1 : 0.35
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: Tokens.fBody
                                        }
                                        HoverHandler { id: ctlHover; cursorShape: ctl.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                        TapHandler {
                                            enabled: ctl.can
                                            onTapped: {
                                                if (ctl.modelData.kind === "lanePrev")
                                                    win.cfg.place(slot.ref, mp.previousLane(laneCard.lane), 999)
                                                else if (ctl.modelData.kind === "laneNext")
                                                    win.cfg.place(slot.ref, mp.nextLane(laneCard.lane), 999)
                                                else if (ctl.modelData.kind === "up")
                                                    win.cfg.place(slot.ref, laneCard.lane, slot.index - 1)
                                                else if (ctl.modelData.kind === "down")
                                                    win.cfg.place(slot.ref, laneCard.lane, slot.index + 1)
                                                else if (ctl.modelData.kind === "style")
                                                    win.cfg.setModuleStyle(slot.ref, mp.nextStyle(slot.ref))
                                                else if (ctl.modelData.kind === "visible")
                                                    win.cfg.setHidden(slot.ref, slot.shown)
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                anchors.left: parent.left; anchors.right: parent.right
                                y: 62; height: 1; color: Tokens.lineSoft
                                opacity: 0.65
                            }

                            Row {
                                id: moduleFine
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: Tokens.s4; anchors.rightMargin: Tokens.s4
                                y: 70; height: 38
                                spacing: Tokens.s4

                                Column {
                                    width: Math.max(150, Math.floor((moduleFine.width - moduleFine.spacing * 2) * 0.38))
                                    spacing: 2
                                    Text { text: I18n.tr("SCALE") + "  " + Math.round(slot.options.scale * 100) + "%"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.letterSpacing: Tokens.trackLabel }
                                    Slid { width: parent.width; height: Tokens.ctlH; from: 0.6; to: 1.6; value: slot.options.scale; onModified: value => win.cfg.setModuleOption(slot.ref, "scale", Math.round(value * 100) / 100) }
                                }
                                Column {
                                    width: 118
                                    spacing: 2
                                    Text { text: I18n.tr("PADDING") + "  " + slot.options.padding; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.letterSpacing: Tokens.trackLabel }
                                    Step { from: 0; to: 20; value: slot.options.padding; onModified: value => win.cfg.setModuleOption(slot.ref, "padding", value) }
                                }
                                Column {
                                    width: Math.max(150, moduleFine.width - x)
                                    spacing: 2
                                    Text { text: I18n.tr("OPACITY") + "  " + Math.round(slot.options.opacity * 100) + "%"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: Tokens.fTiny; font.letterSpacing: Tokens.trackLabel }
                                    Slid { width: parent.width; height: Tokens.ctlH; from: 0.2; to: 1; value: slot.options.opacity; onModified: value => win.cfg.setModuleOption(slot.ref, "opacity", Math.round(value * 100) / 100) }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: I18n.tr("Every lane is real data now. The clock is no longer a pivot: move it, plugins, media, or anything else between LEFT / CENTRE / RIGHT. The palette button cycles each module through plain, paper, outline, accent and ghost treatments. The seal remains Karuma's fixed brand anchor.")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("DEFAULT")
                kana: "初期"
                collapsible: false
                ResetRow { which: "modules"; what: I18n.tr("Restore the shipped three-lane layout and module treatments.") }
            }
        }
    }

    // ── native Ryoku plugins ─────────────────────────────────────────────────
    Component {
        id: pluginsPage
        Column {
            id: pp
            width: pageLoader.width
            spacing: Tokens.s4

            SettingCard {
                width: parent.width
                title: I18n.tr("RYOKU PLUGINS")
                kana: "拡"
                collapsible: false

                Repeater {
                    model: win.pluginHost ? win.pluginHost.barCapable : []
                    delegate: Column {
                        id: plug
                        required property var modelData
                        required property int index
                        readonly property string pid: String(modelData.id || "")
                        readonly property var manifest: modelData.manifest || ({})
                        readonly property bool enabledOnBar: win.pluginHost ? win.pluginHost.isEnabled(pid) : false
                        readonly property var settings: manifest && manifest.metadata
                            && Array.isArray(manifest.metadata.settings) ? manifest.metadata.settings : []
                        width: parent ? parent.width : 0

                        SettingRow {
                            width: parent.width
                            divider: plug.index > 0
                            controlWidth: 54
                            label: String(plug.manifest.name || plug.pid)
                            desc: String(plug.manifest.description || I18n.tr("Native Ryoku top-bar plugin"))
                            source: "plugins.json"
                            Sw {
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                on: plug.enabledOnBar
                                onToggled: value => { if (win.pluginHost) win.pluginHost.setEnabled(plug.pid, value) }
                            }
                        }

                        Item {
                            width: parent.width
                            height: plug.enabledOnBar && plug.settings.length > 0 ? pluginSettings.implicitHeight + Tokens.s4 * 2 : 0
                            clip: true
                            opacity: height > 0 ? 1 : 0
                            Behavior on height { NumberAnimation { duration: Tokens.swap; easing.type: Tokens.ease } }
                            Behavior on opacity { NumberAnimation { duration: Tokens.flap } }
                            Column {
                                id: pluginSettings
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.leftMargin: Tokens.s4
                                anchors.rightMargin: Tokens.s4
                                anchors.topMargin: Tokens.s3
                                spacing: Tokens.s3
                                Repeater {
                                    model: plug.settings
                                    delegate: PluginSetting {
                                        required property var modelData
                                        entry: plug.modelData
                                        setting: modelData
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width - Tokens.s4 * 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: !win.pluginHost || win.pluginHost.barCapable.length === 0
                    text: I18n.tr("No installed plugin currently declares the topbarGlyph host.")
                    color: Tokens.inkFaint
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    wrapMode: Text.WordWrap
                }
            }

            SettingCard {
                width: parent.width
                title: I18n.tr("OMARCHY COMPATIBILITY")
                kana: "互換"
                collapsible: false

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    label: I18n.tr("Adapter status")
                    desc: I18n.tr("Karuma does not directly execute Omarchy bar-widget QML yet. Nomarchy's ABI injects a shell API, widget registry, app library, bar state and service proxies, so loading those files as ordinary QML would be unsafe and incomplete. The Karuma layout namespace already reserves omarchy:<id> entries for the adapter without corrupting saved layouts.")
                    source: "compat"
                    value: I18n.tr("PLANNED")
                }
            }

            Text {
                width: parent.width
                text: I18n.tr("Ryoku plugins are native here: their service, glyph, settings and optional panel use Ryoku.PluginKit. Omarchy support will be a real compatibility host, not a pretend Loader that happens to work for one widget and explodes on the next.")
                color: Tokens.inkFaint
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }
        }
    }
}
