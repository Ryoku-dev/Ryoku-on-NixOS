import QtQuick
import QtQuick.Layouts
import Ryoku.Ui.Singletons

Item {
    id: root

    required property PickerState state
    property var args
    property bool shown: false

    signal closeRequested()

    anchors.fill: parent

    property real _reveal: shown ? 1 : 0
    Behavior on _reveal { NumberAnimation { duration: Theme.standard; easing.type: Theme.revealEasing } }
    visible: _reveal > 0.001

    property bool scheduleEnabled: true
    property var rules: []
    property int selectedIndex: -1
    property int foldoutIndex: -1
    // { mode: "none" | "node" | "add", path: [childIndex, ...] } into the selected rule's tree.
    property var editing: ({ mode: "none", path: [] })
    property string nextTrigger: ""
    property bool loaded: false

    readonly property var currentRule: (root.selectedIndex >= 0 && root.selectedIndex < root.rules.length)
        ? root.rules[root.selectedIndex] : null

    readonly property var weekdays: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    readonly property var weatherTags: ["clear", "sunny", "cloudy", "rainy", "snowy", "stormy", "foggy", "windy"]
    readonly property var blockKinds: ["weekday", "weather", "timewindow", "timecmp", "date", "year", "power", "battery", "output", "outputcount", "raw"]

    function reload() {
        Daemon.call("schedule.get", ({}), function(res, err) {
            if (err) {
                root.state.toast(err.message || I18n.tr("The schedule could not be loaded."), "error")
                root.loaded = true
                return
            }
            root.scheduleEnabled = !!(res && res.enabled)
            root.nextTrigger = (res && res.nextTrigger) ? String(res.nextTrigger) : ""
            root.rules = (res && res.rules) ? res.rules : []
            if (root.selectedIndex >= root.rules.length)
                root.selectedIndex = -1
            root.loaded = true
        })
    }

    function persist() {
        Daemon.call("schedule.set", { enabled: root.scheduleEnabled, rules: root.rules }, function(res, err) {
            if (err)
                root.state.toast(err.message || I18n.tr("The schedule could not be saved."), "error")
        })
    }

    function _clone() { return JSON.parse(JSON.stringify(root.rules)) }
    function commitRules(newRules) { root.rules = newRules; root.persist() }

    onShownChanged: if (root.shown) { root.loaded = false; root.reload() }
    Component.onCompleted: if (root.shown) root.reload()
    Connections {
        target: Daemon
        function onReconnected() { if (root.shown) root.reload() }
    }

    function _close() { root.persist(); root.closeRequested() }

    function defaultCondition() { return { op: "all", negated: false, children: [] } }
    function defaultRule() {
        return {
            name: "", enabled: true, priority: root.rules.length,
            target: { type: "random", value: "", filters: { types: ["static", "video", "we"], favouritesOnly: false } },
            theme: "keep", condition: root.defaultCondition()
        }
    }
    function defaultPredicate(kind) {
        switch (kind) {
            case "weekday": return { block: "weekday", negated: false, days: ["sat", "sun"] }
            case "weather": return { block: "weather", negated: false, tags: ["cloudy"] }
            case "timewindow": return { block: "timewindow", negated: false, from: "sunrise", to: "sunset" }
            case "timecmp": return { block: "timecmp", negated: false, op: ">=", at: "20:00" }
            case "date": return { block: "date", negated: false, value: "12-25" }
            case "year": return { block: "year", negated: false, op: "", value: "2026" }
            case "power": return { block: "power", negated: false, source: "battery" }
            case "battery": return { block: "battery", negated: false, op: "<=", value: "30" }
            case "output": return { block: "output", negated: false, value: "DP-1" }
            case "outputcount": return { block: "outputcount", negated: false, op: ">=", value: "2" }
        }
        return { block: "raw", negated: false, value: "" }
    }

    function _mutateRule(i, fn) {
        var rules = root._clone()
        if (i < 0 || i >= rules.length)
            return
        fn(rules[i])
        root.commitRules(rules)
    }
    function _renumber(rules) { for (var k = 0; k < rules.length; k++) rules[k].priority = k }

    function addRule() {
        var rules = root._clone()
        rules.push(root.defaultRule())
        var i = rules.length - 1
        root.commitRules(rules)
        root.selectedIndex = i
        root.foldoutIndex = i
        root.editAdd([])
    }
    function removeRule(i) {
        var rules = root._clone()
        if (i < 0 || i >= rules.length)
            return
        rules.splice(i, 1)
        root._renumber(rules)
        root.commitRules(rules)
        if (root.selectedIndex === i) {
            root.selectedIndex = -1
            root.foldoutIndex = -1
            root.clearEditing()
        } else if (root.selectedIndex > i) {
            root.selectedIndex -= 1
        }
    }
    function selectRule(i) { root.selectedIndex = i; root.clearEditing() }
    function setRuleEnabled(i, en) { root._mutateRule(i, function(r) { r.enabled = en }) }
    function setScheduleEnabled(en) {
        root.scheduleEnabled = en
        root.persist()
        Settings.set("schedule.enabled", en)
    }
    function moveRule(i, dir) {
        var j = i + dir
        var rules = root._clone()
        if (i < 0 || i >= rules.length || j < 0 || j >= rules.length)
            return
        var tmp = rules[i]; rules[i] = rules[j]; rules[j] = tmp
        root._renumber(rules)
        root.commitRules(rules)
        if (root.selectedIndex === i) root.selectedIndex = j
        else if (root.selectedIndex === j) root.selectedIndex = i
        if (root.foldoutIndex === i) root.foldoutIndex = j
        else if (root.foldoutIndex === j) root.foldoutIndex = i
    }

    function setRuleName(name) { root._mutateRule(root.selectedIndex, function(r) { r.name = name }) }
    function setTargetType(t) { root._mutateRule(root.selectedIndex, function(r) { if (!r.target) r.target = {}; r.target.type = t }) }
    function setTargetValue(v) { root._mutateRule(root.selectedIndex, function(r) { if (!r.target) r.target = {}; r.target.value = v }) }
    function setTheme(mode) { root._mutateRule(root.selectedIndex, function(r) { r.theme = mode }) }
    function _ensureFilters(r) {
        if (!r.target) r.target = {}
        if (!r.target.filters) r.target.filters = { types: ["static", "video", "we"], favouritesOnly: false }
        if (!r.target.filters.types) r.target.filters.types = []
        return r.target.filters
    }
    function toggleTargetFilterType(t) {
        root._mutateRule(root.selectedIndex, function(r) {
            var f = root._ensureFilters(r)
            var arr = f.types.slice()
            var idx = arr.indexOf(t)
            if (idx >= 0) { if (arr.length > 1) arr.splice(idx, 1) }
            else arr.push(t)
            f.types = arr
        })
    }
    function setTargetFavouritesOnly(b) {
        root._mutateRule(root.selectedIndex, function(r) { root._ensureFilters(r).favouritesOnly = b })
    }
    function targetFilters(rule) {
        if (rule && rule.target && rule.target.filters)
            return rule.target.filters
        return { types: ["static", "video", "we"], favouritesOnly: false }
    }

    function editNode(path) { root.editing = { mode: "node", path: path } }
    function editAdd(path) { root.editing = { mode: "add", path: path } }
    function clearEditing() { root.editing = { mode: "none", path: [] } }
    function pathEquals(a, b) {
        if (!a || !b || a.length !== b.length) return false
        for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
        return true
    }
    function nodeAt(cond, path) {
        if (!cond) return null
        var n = cond
        for (var i = 0; i < path.length; i++) {
            if (!n.children || path[i] >= n.children.length) return null
            n = n.children[path[i]]
        }
        return n
    }

    function _mutateNode(path, fn) {
        var rules = root._clone()
        var rule = rules[root.selectedIndex]
        if (!rule) return
        if (!rule.condition) rule.condition = root.defaultCondition()
        var node = root.nodeAt(rule.condition, path)
        if (!node) return
        fn(node)
        root.commitRules(rules)
    }
    function addBlock(path, kind) {
        var rules = root._clone()
        var rule = rules[root.selectedIndex]
        if (!rule) return
        if (!rule.condition) rule.condition = root.defaultCondition()
        var g = root.nodeAt(rule.condition, path)
        if (!g || g.children === undefined) return
        g.children.push(root.defaultPredicate(kind))
        var newPath = path.concat([g.children.length - 1])
        root.commitRules(rules)
        root.editNode(newPath)
    }
    function addGroup(path, isAny) {
        var rules = root._clone()
        var rule = rules[root.selectedIndex]
        if (!rule) return
        if (!rule.condition) rule.condition = root.defaultCondition()
        var g = root.nodeAt(rule.condition, path)
        if (!g || g.children === undefined) return
        g.children.push({ op: isAny ? "any" : "all", negated: false, children: [] })
        var newPath = path.concat([g.children.length - 1])
        root.commitRules(rules)
        root.editNode(newPath)
    }
    function removeNode(path) {
        if (!path || path.length === 0) return
        var rules = root._clone()
        var rule = rules[root.selectedIndex]
        if (!rule) return
        var parent = root.nodeAt(rule.condition, path.slice(0, path.length - 1))
        if (!parent || !parent.children) return
        parent.children.splice(path[path.length - 1], 1)
        root.commitRules(rules)
        root.clearEditing()
    }
    function toggleVal(path, field, item, minKeep) {
        root._mutateNode(path, function(p) {
            var arr = p[field] ? p[field].slice() : []
            var idx = arr.indexOf(item)
            if (idx >= 0) { if (arr.length > minKeep) arr.splice(idx, 1) }
            else arr.push(item)
            p[field] = arr
        })
    }
    function setPredField(path, field, value) { root._mutateNode(path, function(p) { p[field] = value }) }
    function setNegated(path, neg) { root._mutateNode(path, function(p) { p.negated = neg }) }
    function setGroupOp(path, op) { root._mutateNode(path, function(p) { p.op = op }) }
    function resetCondition() {
        root._mutateRule(root.selectedIndex, function(r) { r.condition = root.defaultCondition() })
        root.clearEditing()
    }

    function conditionValid(cond) {
        if (!cond || typeof cond !== "object") return false
        if (typeof cond.raw === "string" && cond.raw.indexOf("condition:") === 0) return false
        return cond.op !== undefined && cond.children !== undefined
    }

    function friendlyList(items) {
        if (!items || items.length === 0) return I18n.tr("nothing")
        if (items.length === 1) return items[0]
        if (items.length === 2) return items[0] + " " + I18n.tr("or") + " " + items[1]
        return items.slice(0, items.length - 1).join(", ") + ", " + I18n.tr("or") + " " + items[items.length - 1]
    }
    function _relationWord(op) {
        switch (op) {
            case "": return I18n.tr("exactly")
            case ">=": return I18n.tr("at least")
            case "<=": return I18n.tr("at most")
            case ">": return I18n.tr("after")
            case "<": return I18n.tr("before")
        }
        return op
    }
    function _sortWeekday(a, b) { return root.weekdays.indexOf(a) - root.weekdays.indexOf(b) }
    function _dateLabel(v) { return v ? v.replace("..", " " + I18n.tr("through") + " ") : "" }
    function timeLabel(v) {
        if (!v) return ""
        var m = /^(sunrise|sunset)([+-]\d+)?$/.exec(v)
        if (m) {
            var solar = m[1] === "sunrise" ? I18n.tr("sunrise") : I18n.tr("sunset")
            if (!m[2]) return solar
            var n = parseInt(m[2], 10)
            var dir = n < 0 ? I18n.tr("before") : I18n.tr("after")
            return Math.abs(n) + " " + I18n.tr("min") + " " + dir + " " + solar
        }
        return v
    }
    function weekdayLabel(d) {
        switch (d) {
            case "mon": return I18n.tr("Monday")
            case "tue": return I18n.tr("Tuesday")
            case "wed": return I18n.tr("Wednesday")
            case "thu": return I18n.tr("Thursday")
            case "fri": return I18n.tr("Friday")
            case "sat": return I18n.tr("Saturday")
            case "sun": return I18n.tr("Sunday")
        }
        return d
    }
    function weatherLabel(t) {
        switch (t) {
            case "clear": return I18n.tr("Clear")
            case "sunny": return I18n.tr("Sunny")
            case "cloudy": return I18n.tr("Cloudy")
            case "rainy": return I18n.tr("Rainy")
            case "snowy": return I18n.tr("Snowy")
            case "stormy": return I18n.tr("Stormy")
            case "foggy": return I18n.tr("Foggy")
            case "windy": return I18n.tr("Windy")
        }
        return t
    }
    function blockKindName(k) {
        switch (k) {
            case "weekday": return I18n.tr("Weekday")
            case "weather": return I18n.tr("Weather")
            case "timewindow": return I18n.tr("Time window")
            case "timecmp": return I18n.tr("Time comparison")
            case "date": return I18n.tr("Date")
            case "year": return I18n.tr("Year")
            case "power": return I18n.tr("Power source")
            case "battery": return I18n.tr("Battery")
            case "output": return I18n.tr("Display output")
            case "outputcount": return I18n.tr("Display count")
            case "raw": return I18n.tr("Raw condition")
        }
        return k
    }
    function conditionSentence(p) {
        if (!p) return ""
        switch (p.block) {
            case "weekday":
                return I18n.tr("Day is") + " " + root.friendlyList((p.days || []).slice().sort(root._sortWeekday).map(function(d) { return root.weekdayLabel(d) }))
            case "weather":
                return I18n.tr("Weather is") + " " + root.friendlyList((p.tags || []).map(function(t) { return root.weatherLabel(t) }))
            case "timewindow":
                return I18n.tr("Time is between") + " " + root.timeLabel(p.from) + " " + I18n.tr("and") + " " + root.timeLabel(p.to)
            case "timecmp":
                return I18n.tr("Time is") + " " + (p.op === ">=" ? I18n.tr("after") : I18n.tr("before")) + " " + root.timeLabel(p.at)
            case "date":
                return I18n.tr("Date is") + " " + root._dateLabel(p.value)
            case "year":
                return I18n.tr("Year is") + " " + root._relationWord(p.op) + " " + (p.value || "")
            case "power":
                return I18n.tr("Power source is") + " " + (p.source === "battery" ? I18n.tr("Battery power") : I18n.tr("External power"))
            case "battery":
                return I18n.tr("Battery is") + " " + root._relationWord(p.op) + " " + (p.value || "") + "%"
            case "output":
                return I18n.tr("Display") + " " + (p.value || "") + " " + I18n.tr("is connected")
            case "outputcount":
                return I18n.tr("Connected display count is") + " " + root._relationWord(p.op) + " " + (p.value || "")
            case "raw":
                if (p.value && p.value.indexOf("condition:") === 0) return I18n.tr("This rule needs its conditions set up")
                return I18n.tr("Unsupported condition:") + " " + (p.value || "")
        }
        return ""
    }
    function predicateDetail(p) { return (p && p.negated) ? I18n.tr("This condition must not match") : I18n.tr("This condition must match") }
    function nodeEyebrow(n, isRoot) {
        if (n && n.block !== undefined) return I18n.tr("Condition")
        return isRoot ? I18n.tr("Rule conditions") : I18n.tr("Nested group")
    }
    function groupTitle(n) {
        if (!n) return ""
        if (!n.children || n.children.length === 0) {
            var always = (n.op === "all") !== (n.negated === true)
            return always ? I18n.tr("Run every time") : I18n.tr("Never run")
        }
        if (n.op === "all") return n.negated ? I18n.tr("Do not match all of these") : I18n.tr("Match all of these")
        return n.negated ? I18n.tr("Match none of these") : I18n.tr("Match any of these")
    }
    function groupDetail(n) {
        if (!n) return ""
        if (!n.children || n.children.length === 0) {
            var always = (n.op === "all") !== (n.negated === true)
            return always ? I18n.tr("No conditions added - this rule currently runs every time")
                          : I18n.tr("No conditions added - this rule is currently disabled")
        }
        return n.op === "all" ? I18n.tr("Every condition below must match")
                              : I18n.tr("At least one condition below must match")
    }
    function connector(idx, op) {
        if (idx === 0) return I18n.tr("If")
        return op === "all" ? I18n.tr("And") : I18n.tr("Or")
    }
    function conditionSummary(cond) {
        if (!root.conditionValid(cond)) return I18n.tr("Needs condition setup")
        return root._summaryNode(cond)
    }
    function _summaryNode(n) {
        if (n.block !== undefined) {
            var s = root.conditionSentence(n)
            return n.negated ? I18n.tr("Not:") + " " + s : s
        }
        if (!n.children || n.children.length === 0) {
            var always = (n.op === "all") !== (n.negated === true)
            return always ? I18n.tr("Always") : I18n.tr("Never")
        }
        var word = n.op === "all" ? I18n.tr("Match all of") : I18n.tr("Match any of")
        var base = word + " " + n.children.length + " " + (n.children.length === 1 ? I18n.tr("condition") : I18n.tr("conditions"))
        return n.negated ? I18n.tr("Not:") + " " + base : base
    }
    function targetTypeLabel(type) {
        switch (type) {
            case "wallpaper": return I18n.tr("Wallpaper")
            case "folder": return I18n.tr("Folder")
            case "playlist": return I18n.tr("Playlist")
        }
        return I18n.tr("Random")
    }
    function targetLabel(rule) {
        if (!rule || !rule.target) return I18n.tr("Random")
        var t = rule.target
        if (!t.type || t.type === "random") return I18n.tr("Random")
        if (t.value && t.value.length) return t.value
        return root.targetTypeLabel(t.type)
    }
    function targetValuePlaceholder(type) {
        switch (type) {
            case "wallpaper": return I18n.tr("library key, static:foo.png, video:clip.mp4, or we:123")
            case "folder": return I18n.tr("folder name or path")
            case "playlist": return I18n.tr("playlist ID")
        }
        return I18n.tr("random")
    }
    function themeLabel(mode) {
        switch (mode) {
            case "light": return I18n.tr("Light")
            case "dark": return I18n.tr("Dark")
        }
        return I18n.tr("Keep current")
    }
    function editorTitle() {
        var e = root.editing
        if (e.mode === "add") return I18n.tr("Add to this group")
        if (e.mode === "node" && root.currentRule) {
            var n = root.nodeAt(root.currentRule.condition, e.path)
            if (n && n.block !== undefined) return root.blockKindName(n.block)
            if (n) return I18n.tr("Group settings")
        }
        return I18n.tr("Edit conditions")
    }
    function editorDesc() {
        var e = root.editing
        if (e.mode === "add" || e.mode === "node") return I18n.tr("Changes save immediately.")
        return I18n.tr("Select something in the condition list to show its controls.")
    }

    component SchedSection: Item {
        id: sectionRoot
        property string sTitle: ""
        property string sDesc: ""
        default property alias sBody: bodyCol.data
        implicitHeight: outer.implicitHeight

        Column {
            id: outer
            width: sectionRoot.width
            spacing: 11 * Theme.scale

            FolioRule { width: outer.width; alpha: 0.56 }
            Text {
                text: sectionRoot.sTitle
                font.family: Theme.sans
                font.weight: Font.DemiBold
                font.pixelSize: Theme.fontField
                color: Theme.surfaceText
                renderType: Text.NativeRendering
            }
            Text {
                width: outer.width
                visible: sectionRoot.sDesc.length > 0
                text: sectionRoot.sDesc
                font.family: Theme.sans
                font.weight: Font.Normal
                font.pixelSize: Theme.fontBase
                color: Theme.withAlpha(Theme.surfaceText, 0.5)
                lineHeight: 1.4
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
            }
            Column {
                id: bodyCol
                width: outer.width
                spacing: 9 * Theme.scale
            }
        }
    }

    FolioSheet {
        id: sheet
        reveal: root._reveal
        onDismissed: root._close()

        FolioMasthead {
            parent: sheet.mastheadArea
            anchors.fill: parent
            breadcrumb: I18n.tr("Schedule") + "  /  "
                + (root.currentRule ? (root.currentRule.name && root.currentRule.name.length ? root.currentRule.name : I18n.tr("Unnamed rule"))
                                    : I18n.tr("Rules"))
            onCloseRequested: root._close()
        }

        FolioIndexShell {
            id: indexShell
            parent: sheet.indexArea
            anchors.fill: parent
            title: I18n.tr("Schedule")
            note: I18n.tr("Rules are read from top to bottom. The first matching rule wins.")

            SchedulePriorityIndex {
                parent: indexShell.body
                sheet: root
                rules: root.rules
                scheduleEnabled: root.scheduleEnabled
                selectedIndex: root.selectedIndex
                foldoutIndex: root.foldoutIndex
                loaded: root.loaded
            }
        }

        Item {
            id: reading
            parent: sheet.readingArea
            anchors.fill: parent

            Column {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.leftMargin: 36 * Theme.scale
                anchors.rightMargin: 36 * Theme.scale
                anchors.topMargin: 36 * Theme.scale
                spacing: 8 * Theme.scale
                visible: root.loaded && root.currentRule === null

                Text {
                    text: I18n.tr("Schedule / rules")
                    font.family: Theme.sans
                    font.weight: Font.Medium
                    font.pixelSize: Theme.fontFine
                    color: Theme.withAlpha(Theme.surfaceText, 0.54)
                    renderType: Text.NativeRendering
                }
                Text {
                    text: I18n.tr("Build a schedule")
                    font.family: Theme.display
                    font.pixelSize: Theme.fontStudio
                    color: Theme.surfaceText
                    renderType: Text.NativeRendering
                }
                Text {
                    width: parent.width
                    text: I18n.tr("Create a rule in the index. Rules run from top to bottom and save as you edit.")
                    font.family: Theme.sans
                    font.weight: Font.Normal
                    font.pixelSize: Theme.fontXSmall
                    color: Theme.withAlpha(Theme.surfaceText, 0.58)
                    lineHeight: 1.4
                    wrapMode: Text.WordWrap
                    renderType: Text.NativeRendering
                }
            }

            Loader {
                anchors.fill: parent
                active: root.currentRule !== null
                sourceComponent: formComp
            }
        }
    }

    Component {
        id: formComp

        Flickable {
            id: flick
            clip: true
            contentWidth: width
            contentHeight: page.implicitHeight + 74 * Theme.scale
            boundsBehavior: Flickable.StopAtBounds

            readonly property real pad: 34 * Theme.scale
            readonly property real contentW: flick.width - pad * 2
            readonly property bool wide: contentW >= 780 * Theme.scale

            Column {
                id: page
                x: flick.pad
                y: 32 * Theme.scale
                width: flick.contentW
                spacing: 28 * Theme.scale

                Column {
                    width: parent.width
                    spacing: 8 * Theme.scale

                    RowLayout {
                        width: parent.width
                        Text {
                            text: I18n.tr("Schedule / rule")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.54)
                            renderType: Text.NativeRendering
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: I18n.tr("Saved")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontFine
                            color: Theme.withAlpha(Theme.surfaceText, 0.46)
                            renderType: Text.NativeRendering
                        }
                    }

                    Text {
                        width: parent.width * 0.72
                        text: (root.currentRule && root.currentRule.name && root.currentRule.name.length)
                            ? root.currentRule.name : I18n.tr("Unnamed rule")
                        font.family: Theme.display
                        font.pixelSize: Theme.fontStudio
                        color: Theme.surfaceText
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                    }

                    Text {
                        visible: root.nextTrigger.length > 0
                        text: I18n.tr("Next change") + "  \u00b7  " + root.nextTrigger
                        font.family: Theme.sans
                        font.weight: Font.Normal
                        font.pixelSize: Theme.fontFine
                        color: Theme.withAlpha(Theme.surfaceText, 0.5)
                        renderType: Text.NativeRendering
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 10 * Theme.scale
                        Text {
                            Layout.alignment: Qt.AlignTop
                            text: I18n.tr("When")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fs(8.5)
                            color: Theme.withAlpha(Theme.surfaceText, 0.54)
                            renderType: Text.NativeRendering
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.currentRule ? root.conditionSummary(root.currentRule.condition) : ""
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontBase
                            color: Theme.withAlpha(Theme.surfaceText, 0.74)
                            wrapMode: Text.WordWrap
                            renderType: Text.NativeRendering
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 10 * Theme.scale
                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: I18n.tr("Then")
                            font.family: Theme.sans
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fs(8.5)
                            color: Theme.withAlpha(Theme.surfaceText, 0.54)
                            renderType: Text.NativeRendering
                        }
                        Text {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: root.currentRule
                                ? (I18n.tr("Apply") + " " + root.targetLabel(root.currentRule) + "  \u00b7  " + root.themeLabel(root.currentRule.theme))
                                : ""
                            font.family: Theme.sans
                            font.weight: Font.Normal
                            font.pixelSize: Theme.fontXSmall
                            color: Theme.withAlpha(Theme.surfaceText, 0.74)
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                        }
                        FolioDestructiveAction {
                            Layout.alignment: Qt.AlignVCenter
                            fixedWidth: 116 * Theme.scale
                            confirm: true
                            label: I18n.tr("Delete rule")
                            glyph: "\uf1f8"
                            onTriggered: root.removeRule(root.selectedIndex)
                        }
                    }
                }

                GridLayout {
                    width: parent.width
                    columns: flick.wide ? 3 : 1
                    columnSpacing: 22 * Theme.scale
                    rowSpacing: 18 * Theme.scale

                    Column {
                        id: defCol
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: flick.wide ? flick.contentW * 0.38 : 0
                        Layout.fillWidth: !flick.wide
                        spacing: 15 * Theme.scale

                        SchedSection {
                            width: defCol.width
                            sTitle: I18n.tr("Rule name")
                            sDesc: I18n.tr("Give the rule a short name so it is easy to recognise in the priority list.")

                            TextField {
                                id: nameField
                                width: parent.width
                                variant: "field"
                                placeholder: I18n.tr("Rule name")
                                text: root.currentRule ? (root.currentRule.name || "") : ""
                                onCommitted: (t) => root.setRuleName(t)
                                Connections {
                                    target: root
                                    function onSelectedIndexChanged() {
                                        if (!nameField.editing)
                                            nameField.text = root.currentRule ? (root.currentRule.name || "") : ""
                                    }
                                }
                            }
                        }

                        SchedSection {
                            width: defCol.width
                            sTitle: I18n.tr("Wallpaper")
                            sDesc: I18n.tr("Pick what this rule applies when it is the first match: a random pick, one wallpaper, a folder, or a playlist.")

                            ChoiceButtons {
                                width: parent.width
                                value: root.currentRule && root.currentRule.target ? (root.currentRule.target.type || "random") : "random"
                                options: [
                                    { value: "random", label: I18n.tr("Random") },
                                    { value: "wallpaper", label: I18n.tr("Wallpaper") },
                                    { value: "folder", label: I18n.tr("Folder") },
                                    { value: "playlist", label: I18n.tr("Playlist") }
                                ]
                                onSelected: (v) => root.setTargetType(v)
                            }

                            TextField {
                                id: targetValueField
                                width: parent.width
                                visible: root.currentRule && root.currentRule.target && root.currentRule.target.type
                                    && root.currentRule.target.type !== "random"
                                variant: "field"
                                placeholder: root.currentRule && root.currentRule.target
                                    ? root.targetValuePlaceholder(root.currentRule.target.type) : ""
                                text: root.currentRule && root.currentRule.target ? (root.currentRule.target.value || "") : ""
                                onCommitted: (t) => root.setTargetValue(t.trim())
                                Connections {
                                    target: root
                                    function onSelectedIndexChanged() {
                                        if (!targetValueField.editing)
                                            targetValueField.text = root.currentRule && root.currentRule.target
                                                ? (root.currentRule.target.value || "") : ""
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 7 * Theme.scale
                                visible: root.currentRule && root.currentRule.target
                                    && (root.currentRule.target.type === "random" || root.currentRule.target.type === "folder")

                                Text {
                                    text: I18n.tr("Pool filters")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fontFine
                                    color: Theme.withAlpha(Theme.surfaceText, 0.54)
                                    renderType: Text.NativeRendering
                                }
                                Flow {
                                    width: parent.width
                                    spacing: 7 * Theme.scale
                                    Repeater {
                                        model: [
                                            { value: "static", label: I18n.tr("Images") },
                                            { value: "video", label: I18n.tr("Video") },
                                            { value: "we", label: I18n.tr("Wallpaper Engine") }
                                        ]
                                        delegate: FixedButton {
                                            required property var modelData
                                            label: modelData.label
                                            active: root.currentRule
                                                ? root.targetFilters(root.currentRule).types.indexOf(modelData.value) >= 0 : false
                                            onTriggered: root.toggleTargetFilterType(modelData.value)
                                        }
                                    }
                                }
                                ChoiceButtons {
                                    width: parent.width
                                    value: root.currentRule ? root.targetFilters(root.currentRule).favouritesOnly === true : false
                                    options: [
                                        { value: false, label: I18n.tr("All wallpapers") },
                                        { value: true, label: I18n.tr("Favourites only") }
                                    ]
                                    onSelected: (v) => root.setTargetFavouritesOnly(v)
                                }
                            }
                        }

                        SchedSection {
                            width: defCol.width
                            sTitle: I18n.tr("Theme")
                            sDesc: I18n.tr("Keep the current theme, or switch it when this rule is the first match.")

                            ChoiceButtons {
                                width: parent.width
                                value: root.currentRule ? (root.currentRule.theme || "keep") : "keep"
                                options: [
                                    { value: "keep", label: I18n.tr("Keep current") },
                                    { value: "light", label: I18n.tr("Light") },
                                    { value: "dark", label: I18n.tr("Dark") }
                                ]
                                onSelected: (v) => root.setTheme(v)
                            }
                        }
                    }

                    Rectangle {
                        visible: flick.wide
                        Layout.fillHeight: true
                        implicitWidth: 1
                        color: Theme.withAlpha(Theme.outline, 0.36)
                    }

                    Column {
                        id: condCol
                        Layout.alignment: Qt.AlignTop
                        Layout.fillWidth: true
                        spacing: 15 * Theme.scale

                        SchedSection {
                            width: condCol.width
                            sTitle: I18n.tr("When should this rule run?")
                            sDesc: I18n.tr("Start with normal conditions. Add a nested group only when you need mixed all/any logic.")

                            Column {
                                width: parent.width
                                spacing: 8 * Theme.scale
                                visible: !(root.currentRule && root.conditionValid(root.currentRule.condition))

                                Text {
                                    width: parent.width
                                    text: I18n.tr("Set up this rule's conditions")
                                    font.family: Theme.sans
                                    font.weight: Font.Medium
                                    font.pixelSize: Theme.fontBase
                                    color: Theme.surfaceText
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }
                                Text {
                                    width: parent.width
                                    text: I18n.tr("This unfinished rule has no usable condition tree. Start fresh, then add conditions in plain language.")
                                    font.family: Theme.sans
                                    font.weight: Font.Normal
                                    font.pixelSize: Theme.fs(8.8)
                                    color: Theme.withAlpha(Theme.surfaceText, 0.5)
                                    lineHeight: 1.35
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }
                                FolioAction {
                                    fixedWidth: 210 * Theme.scale
                                    label: I18n.tr("Start with no conditions")
                                    onTriggered: root.resetCondition()
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 9 * Theme.scale
                                visible: root.currentRule && root.conditionValid(root.currentRule.condition)

                                ScheduleConditionNode {
                                    width: parent.width
                                    sheet: root
                                    model: root.currentRule ? root.currentRule.condition : null
                                    path: []
                                    depth: 0
                                }
                                Text {
                                    width: parent.width
                                    text: I18n.tr("Use groups only when one rule needs a mix of all/any logic.")
                                    font.family: Theme.sans
                                    font.weight: Font.Normal
                                    font.pixelSize: Theme.fontBase
                                    color: Theme.withAlpha(Theme.surfaceText, 0.42)
                                    lineHeight: 1.35
                                    wrapMode: Text.WordWrap
                                    renderType: Text.NativeRendering
                                }
                            }
                        }

                        SchedSection {
                            width: condCol.width
                            sTitle: root.editorTitle()
                            sDesc: root.editorDesc()
                            visible: root.currentRule && root.conditionValid(root.currentRule.condition)

                            ScheduleConditionEditor {
                                width: parent.width
                                sheet: root
                            }
                        }
                    }
                }
            }
        }
    }

    Keys.onEscapePressed: root._close()
}
